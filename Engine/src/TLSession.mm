#import <TorrlyEngine/TLSession.h>
#import "TLModels+Internal.h"

#include <atomic>
#include <cstdlib>
#include <chrono>
#include <fstream>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/announce_entry.hpp>
#include <libtorrent/ip_filter.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/version.hpp>
#include <libtorrent/write_resume_data.hpp>

namespace lt = libtorrent;

NSErrorDomain const TLErrorDomain = @"TorrlyEngine";

// Same bootstrap set TorrDroid uses (REPORT.md §3.4).
static const char *kDHTBootstrapNodes =
    "dht.libtorrent.org:25401,router.bittorrent.com:6881,router.utorrent.com:6881,dht.transmissionbt.com:6881";

#pragma mark - Helpers

static NSString *TLString(std::string const &s) {
    NSString *result = [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding];
    return result ?: @"";
}

static std::string TLStd(NSString *s) {
    return s ? std::string(s.UTF8String ?: "") : std::string();
}

static NSString *TLHex(lt::sha1_hash const &hash) {
    static const char digits[] = "0123456789abcdef";
    std::string out;
    out.reserve(hash.size() * 2);
    for (auto byte : hash) {
        auto b = static_cast<unsigned char>(byte);
        out.push_back(digits[b >> 4]);
        out.push_back(digits[b & 0xf]);
    }
    return TLString(out);
}

static NSString *TLHex(lt::info_hash_t const &hashes) {
    return TLHex(hashes.get_best());
}

static NSError *TLMakeError(NSString *message) {
    return [NSError errorWithDomain:TLErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSError *TLMakeError(lt::error_code const &ec) {
    return TLMakeError(TLString(ec.message()));
}

static bool TLReadFile(NSString *path, std::vector<char> &out) {
    std::ifstream in(TLStd(path), std::ios::binary);
    if (!in) return false;
    out.assign(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
    return true;
}

static void TLWriteFile(NSString *path, std::vector<char> const &buf) {
    NSString *tmp = [path stringByAppendingString:@".tmp"];
    {
        std::ofstream out(TLStd(tmp), std::ios::binary | std::ios::trunc);
        out.write(buf.data(), static_cast<std::streamsize>(buf.size()));
    }
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    [NSFileManager.defaultManager moveItemAtPath:tmp toPath:path error:nil];
}

static lt::settings_pack::enc_policy TLPolicy(TLEncryptionPolicy p) {
    switch (p) {
        case TLEncryptionPolicyForced: return lt::settings_pack::pe_forced;
        case TLEncryptionPolicyDisabled: return lt::settings_pack::pe_disabled;
        default: return lt::settings_pack::pe_enabled;
    }
}

static lt::settings_pack TLPack(TLSessionSettings *s) {
    lt::settings_pack p;
    p.set_int(lt::settings_pack::alert_mask,
              lt::alert_category::error | lt::alert_category::status | lt::alert_category::storage);
    int port = s.listenPort > 0 ? s.listenPort : 6881;
    char listen[64];
    snprintf(listen, sizeof(listen), "0.0.0.0:%d,[::]:%d", port, port);
    p.set_str(lt::settings_pack::listen_interfaces, listen);
    p.set_bool(lt::settings_pack::enable_dht, s.dhtEnabled);
    p.set_str(lt::settings_pack::dht_bootstrap_nodes, kDHTBootstrapNodes);
    p.set_bool(lt::settings_pack::enable_lsd, true);
    p.set_bool(lt::settings_pack::enable_upnp, true);
    p.set_bool(lt::settings_pack::enable_natpmp, true);
    p.set_int(lt::settings_pack::download_rate_limit, MAX(0, s.maxDownloadRate));
    p.set_int(lt::settings_pack::upload_rate_limit, MAX(0, s.maxUploadRate));
    p.set_int(lt::settings_pack::in_enc_policy, TLPolicy(s.incomingEncryption));
    p.set_int(lt::settings_pack::out_enc_policy, TLPolicy(s.outgoingEncryption));
    p.set_int(lt::settings_pack::allowed_enc_level, lt::settings_pack::pe_both);
    p.set_int(lt::settings_pack::connections_limit, 200);
    p.set_int(lt::settings_pack::active_downloads, 4);
    p.set_int(lt::settings_pack::active_seeds, 4);

    switch (s.proxyType) {
        case TLProxyTypeNone:
            p.set_int(lt::settings_pack::proxy_type, lt::settings_pack::none);
            break;
        case TLProxyTypeSocks4:
            p.set_int(lt::settings_pack::proxy_type, lt::settings_pack::socks4);
            break;
        case TLProxyTypeSocks5:
            p.set_int(lt::settings_pack::proxy_type, s.proxyUsername.length > 0 ? lt::settings_pack::socks5_pw : lt::settings_pack::socks5);
            break;
        case TLProxyTypeHTTP:
            p.set_int(lt::settings_pack::proxy_type, s.proxyUsername.length > 0 ? lt::settings_pack::http_pw : lt::settings_pack::http);
            break;
    }
    if (s.proxyType != TLProxyTypeNone) {
        p.set_str(lt::settings_pack::proxy_hostname, TLStd(s.proxyHost));
        p.set_int(lt::settings_pack::proxy_port, s.proxyPort);
        p.set_str(lt::settings_pack::proxy_username, TLStd(s.proxyUsername));
        p.set_str(lt::settings_pack::proxy_password, TLStd(s.proxyPassword));
    }
    return p;
}

static TLTorrentState TLState(lt::torrent_status const &st) {
    if (st.errc) return TLTorrentStateError;
    if (st.flags & lt::torrent_flags::paused) return TLTorrentStatePaused;
    switch (st.state) {
        case lt::torrent_status::checking_files: return TLTorrentStateCheckingFiles;
        case lt::torrent_status::downloading_metadata: return TLTorrentStateDownloadingMetadata;
        case lt::torrent_status::downloading: return TLTorrentStateDownloading;
        case lt::torrent_status::finished: return TLTorrentStateFinished;
        case lt::torrent_status::seeding: return TLTorrentStateSeeding;
        case lt::torrent_status::checking_resume_data: return TLTorrentStateCheckingResumeData;
        default: return TLTorrentStateDownloading;
    }
}

static TLTorrentStatus *TLMakeStatus(lt::torrent_status const &st) {
    TLTorrentStatus *s = [TLTorrentStatus new];
    s.infoHash = TLHex(st.info_hashes);
    s.name = st.name.empty() ? s.infoHash : TLString(st.name);
    s.savePath = TLString(st.save_path);
    s.state = TLState(st);
    s.isPaused = (st.flags & lt::torrent_flags::paused) ? YES : NO;
    s.hasMetadata = st.has_metadata;
    s.progress = st.progress;
    s.totalWanted = st.total_wanted;
    s.totalWantedDone = st.total_wanted_done;
    s.totalUploaded = st.all_time_upload;
    s.totalDownloaded = st.all_time_download;
    s.downloadRate = st.download_payload_rate;
    s.uploadRate = st.upload_payload_rate;
    s.connectedSeeds = st.num_seeds;
    s.connectedPeers = st.num_peers;
    s.totalSeeds = st.num_complete >= 0 ? st.num_complete : st.list_seeds;
    s.totalPeers = st.num_incomplete >= 0 ? st.num_incomplete : st.list_peers - st.list_seeds;
    s.numPieces = st.num_pieces;
    if (auto ti = st.torrent_file.lock()) {
        s.pieceLength = ti->piece_length();
        s.numPieces = ti->num_pieces();
    }
    s.downloadLimit = st.handle.download_limit();
    s.uploadLimit = st.handle.upload_limit();
    s.errorMessage = st.errc ? TLString(st.errc.message()) : nil;
    s.addedDate = [NSDate dateWithTimeIntervalSince1970:static_cast<NSTimeInterval>(st.added_time)];
    s.completedDate = st.completed_time > 0 ? [NSDate dateWithTimeIntervalSince1970:static_cast<NSTimeInterval>(st.completed_time)] : nil;
    return s;
}

static NSArray<TLFileEntry *> *TLFiles(lt::file_storage const &fs, std::vector<std::int64_t> const *progress,
                                       std::vector<lt::download_priority_t> const *priorities) {
    NSMutableArray<TLFileEntry *> *files = [NSMutableArray array];
    for (lt::file_index_t i : fs.file_range()) {
        if (fs.pad_file_at(i)) continue;
        int idx = static_cast<int>(i);
        int64_t done = progress && idx < (int)progress->size() ? (*progress)[idx] : 0;
        int prio = priorities && idx < (int)priorities->size() ? static_cast<int>(static_cast<std::uint8_t>((*priorities)[idx])) : 4;
        [files addObject:[[TLFileEntry alloc] initWithIndex:idx path:TLString(fs.file_path(i)) size:fs.file_size(i) downloaded:done priority:prio]];
    }
    return files;
}

#pragma mark - Session

@implementation TLSession {
    std::unique_ptr<lt::session> _session;
    std::thread _alertThread;
    std::atomic<bool> _running;
    std::mutex _saveMutex;
    int _pendingResumeSaves;
    NSMutableArray *_saveCompletions;
    NSString *_stateDirectory;
}

+ (NSString *)libtorrentVersion {
    return @(lt::version_str);
}

- (instancetype)initWithSettings:(TLSessionSettings *)settings stateDirectory:(NSString *)stateDirectory {
    if ((self = [super init])) {
        _stateDirectory = [stateDirectory copy];
        _saveCompletions = [NSMutableArray array];
        if (settings.caBundlePath.length > 0) {
            // OpenSSL's default verify paths honour SSL_CERT_FILE; libtorrent validates HTTPS trackers with them.
            setenv("SSL_CERT_FILE", settings.caBundlePath.fileSystemRepresentation, 1);
        }
        [NSFileManager.defaultManager createDirectoryAtPath:[self resumeDirectory] withIntermediateDirectories:YES attributes:nil error:nil];

        lt::session_params params;
        std::vector<char> state;
        if (TLReadFile([self sessionStatePath], state)) {
            try {
                params = lt::read_session_params(state, lt::session_handle::save_dht_state);
            } catch (...) {
                params = lt::session_params();
            }
        }
        params.settings = TLPack(settings);
        _session = std::make_unique<lt::session>(std::move(params));

        // Like TorrDroid: never connect to peers on well-known service ports, except 80 and 443.
        lt::port_filter filter;
        filter.add_rule(0, 79, lt::port_filter::blocked);
        filter.add_rule(81, 442, lt::port_filter::blocked);
        filter.add_rule(444, 1023, lt::port_filter::blocked);
        _session->set_port_filter(filter);

        _running = true;
        __weak TLSession *weakSelf = self;
        _alertThread = std::thread([weakSelf] {
            [NSThread currentThread].name = @"TorrlyEngine-alerts";
            auto lastUpdate = std::chrono::steady_clock::now() - std::chrono::seconds(1);
            auto lastSave = std::chrono::steady_clock::now();
            while (true) {
                @autoreleasepool {
                    TLSession *strongSelf = weakSelf;
                    if (!strongSelf || !strongSelf->_running) break;
                    [strongSelf pumpAlerts];
                    auto now = std::chrono::steady_clock::now();
                    if (now - lastUpdate >= std::chrono::seconds(1)) {
                        lastUpdate = now;
                        [strongSelf postStatuses];
                    }
                    if (now - lastSave >= std::chrono::seconds(60)) {
                        lastSave = now;
                        [strongSelf saveModifiedResumeData];
                    }
                }
            }
        });
    }
    return self;
}

- (void)dealloc {
    [self shutdown];
}

- (NSString *)resumeDirectory {
    return [_stateDirectory stringByAppendingPathComponent:@"resume"];
}

- (NSString *)sessionStatePath {
    return [_stateDirectory stringByAppendingPathComponent:@"session.state"];
}

- (NSString *)resumePathFor:(NSString *)infoHash {
    return [[self resumeDirectory] stringByAppendingPathComponent:[infoHash stringByAppendingPathExtension:@"resume"]];
}

- (void)shutdown {
    if (!_running.exchange(false)) return;
    if (_alertThread.joinable()) {
        if (std::this_thread::get_id() == _alertThread.get_id()) {
            _alertThread.detach();
        } else {
            _alertThread.join();
        }
    }
    if (_session) {
        _session->pause();
        _session.reset();
    }
}

#pragma mark Alerts

- (void)notify:(void (^)(id<TLSessionDelegate> delegate))block {
    __weak TLSession *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        TLSession *strongSelf = weakSelf;
        id<TLSessionDelegate> delegate = strongSelf.delegate;
        if (delegate) block(delegate);
    });
}

- (void)pumpAlerts {
    if (!_session) return;
    _session->wait_for_alert(std::chrono::milliseconds(250));
    std::vector<lt::alert *> alerts;
    _session->pop_alerts(&alerts);
    for (lt::alert *a : alerts) {
        if (auto *added = lt::alert_cast<lt::add_torrent_alert>(a)) {
            if (added->error) {
                NSString *message = TLString(added->error.message());
                [self notify:^(id<TLSessionDelegate> d) { [d session:self torrent:nil didFailWithMessage:message]; }];
            } else {
                added->handle.save_resume_data(lt::torrent_handle::save_info_dict);
            }
        } else if (auto *finished = lt::alert_cast<lt::torrent_finished_alert>(a)) {
            NSString *hash = TLHex(finished->handle.info_hashes());
            finished->handle.save_resume_data(lt::torrent_handle::save_info_dict);
            [self notify:^(id<TLSessionDelegate> d) { [d session:self torrentDidFinish:hash]; }];
        } else if (auto *meta = lt::alert_cast<lt::metadata_received_alert>(a)) {
            NSString *hash = TLHex(meta->handle.info_hashes());
            meta->handle.save_resume_data(lt::torrent_handle::save_info_dict);
            [self notify:^(id<TLSessionDelegate> d) { [d session:self torrentDidReceiveMetadata:hash]; }];
        } else if (auto *saved = lt::alert_cast<lt::save_resume_data_alert>(a)) {
            NSString *hash = TLHex(saved->params.info_hashes);
            TLWriteFile([self resumePathFor:hash], lt::write_resume_data_buf(saved->params));
            [self resumeSaveFinished];
        } else if (lt::alert_cast<lt::save_resume_data_failed_alert>(a)) {
            [self resumeSaveFinished];
        } else if (auto *removed = lt::alert_cast<lt::torrent_removed_alert>(a)) {
            NSString *hash = TLHex(removed->info_hashes);
            [NSFileManager.defaultManager removeItemAtPath:[self resumePathFor:hash] error:nil];
            [self notify:^(id<TLSessionDelegate> d) { [d session:self torrentWasRemoved:hash]; }];
        } else if (auto *err = lt::alert_cast<lt::torrent_error_alert>(a)) {
            NSString *hash = TLHex(err->handle.info_hashes());
            NSString *message = TLString(err->message());
            [self notify:^(id<TLSessionDelegate> d) { [d session:self torrent:hash didFailWithMessage:message]; }];
        } else if (auto *ferr = lt::alert_cast<lt::file_error_alert>(a)) {
            NSString *hash = TLHex(ferr->handle.info_hashes());
            NSString *message = TLString(ferr->message());
            [self notify:^(id<TLSessionDelegate> d) { [d session:self torrent:hash didFailWithMessage:message]; }];
        }
    }
}

- (void)postStatuses {
    NSArray<TLTorrentStatus *> *statuses = [self allStatuses];
    [self notify:^(id<TLSessionDelegate> d) { [d session:self didUpdateTorrents:statuses]; }];
}

/// Keeps progress safe if the app is killed without a chance to save (resume data is otherwise written on
/// add, pause, finish and when the app goes to the background).
- (void)saveModifiedResumeData {
    if (!_session) return;
    std::lock_guard<std::mutex> lock(_saveMutex);
    for (auto const &h : _session->get_torrents()) {
        if (!h.is_valid() || !h.need_save_resume_data()) continue;
        h.save_resume_data(lt::torrent_handle::save_info_dict | lt::torrent_handle::only_if_modified);
        _pendingResumeSaves++;
    }
}

- (void)resumeSaveFinished {
    NSArray *completions = nil;
    {
        std::lock_guard<std::mutex> lock(_saveMutex);
        if (_pendingResumeSaves > 0) _pendingResumeSaves--;
        if (_pendingResumeSaves == 0 && _saveCompletions.count > 0) {
            completions = [_saveCompletions copy];
            [_saveCompletions removeAllObjects];
        }
    }
    for (void (^completion)(void) in completions) {
        dispatch_async(dispatch_get_main_queue(), completion);
    }
}

#pragma mark Lookup

- (lt::torrent_handle)handleFor:(NSString *)infoHash {
    if (!_session) return {};
    for (lt::torrent_handle const &h : _session->get_torrents()) {
        if ([TLHex(h.info_hashes()) isEqualToString:infoHash]) return h;
    }
    return {};
}

#pragma mark Public API

- (void)restoreTorrentsWithSavePath:(NSString *)savePath {
    NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:[self resumeDirectory] error:nil];
    for (NSString *name in names) {
        if (![name.pathExtension isEqualToString:@"resume"]) continue;
        std::vector<char> buf;
        if (!TLReadFile([[self resumeDirectory] stringByAppendingPathComponent:name], buf)) continue;
        lt::error_code ec;
        lt::add_torrent_params atp = lt::read_resume_data(buf, ec);
        if (ec) continue;
        // iOS gives the app a new container path after reinstalls and restores; a saved folder outside the
        // current home directory belongs to an old container.
        NSString *saved = TLString(atp.save_path).stringByStandardizingPath;
        NSString *home = NSHomeDirectory().stringByStandardizingPath;
        if (![saved hasPrefix:[home stringByAppendingString:@"/"]]) {
            atp.save_path = TLStd(savePath);
        }
        _session->async_add_torrent(std::move(atp));
    }
}

- (void)applySettings:(TLSessionSettings *)settings {
    if (_session) _session->apply_settings(TLPack(settings));
}

+ (NSString *)infoHashOfMagnet:(NSString *)uri {
    lt::error_code ec;
    lt::add_torrent_params atp = lt::parse_magnet_uri(TLStd(uri), ec);
    if (ec) return nil;
    return TLHex(atp.info_hashes);
}

- (NSString *)addMagnet:(NSString *)uri savePath:(NSString *)savePath error:(NSError **)error {
    lt::error_code ec;
    lt::add_torrent_params atp = lt::parse_magnet_uri(TLStd(uri), ec);
    if (ec) {
        if (error) *error = TLMakeError(ec);
        return nil;
    }
    atp.save_path = TLStd(savePath);
    NSString *hash = TLHex(atp.info_hashes);
    if ([self handleFor:hash].is_valid()) return hash;
    _session->async_add_torrent(std::move(atp));
    return hash;
}

+ (TLTorrentInfo *)readTorrentFile:(NSString *)path error:(NSError **)error {
    lt::error_code ec;
    auto ti = std::make_shared<lt::torrent_info>(TLStd(path), ec);
    if (ec) {
        if (error) *error = TLMakeError(ec);
        return nil;
    }
    NSMutableArray<NSString *> *trackers = [NSMutableArray array];
    for (auto const &t : ti->trackers()) [trackers addObject:TLString(t.url)];
    return [[TLTorrentInfo alloc] initWithInfoHash:TLHex(ti->info_hashes())
                                              name:TLString(ti->name())
                                         totalSize:ti->total_size()
                                         numPieces:ti->num_pieces()
                                             files:TLFiles(ti->files(), nullptr, nullptr)
                                          trackers:trackers];
}

- (NSString *)addTorrentFile:(NSString *)path savePath:(NSString *)savePath filePriorities:(NSArray<NSNumber *> *)filePriorities error:(NSError **)error {
    lt::error_code ec;
    auto ti = std::make_shared<lt::torrent_info>(TLStd(path), ec);
    if (ec) {
        if (error) *error = TLMakeError(ec);
        return nil;
    }
    NSString *hash = TLHex(ti->info_hashes());
    if ([self handleFor:hash].is_valid()) return hash;
    lt::add_torrent_params atp;
    atp.ti = ti;
    atp.save_path = TLStd(savePath);
    if (filePriorities.count > 0) {
        for (NSNumber *p in filePriorities) {
            atp.file_priorities.push_back(lt::download_priority_t{static_cast<std::uint8_t>(p.intValue)});
        }
    }
    _session->async_add_torrent(std::move(atp));
    return hash;
}

- (void)pauseTorrent:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    h.unset_flags(lt::torrent_flags::auto_managed);
    h.pause(lt::torrent_handle::graceful_pause);
    h.save_resume_data(lt::torrent_handle::save_info_dict);
}

- (void)resumeTorrent:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    h.set_flags(lt::torrent_flags::auto_managed);
    h.resume();
}

- (void)removeTorrent:(NSString *)infoHash deleteFiles:(BOOL)deleteFiles {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) {
        [NSFileManager.defaultManager removeItemAtPath:[self resumePathFor:infoHash] error:nil];
        return;
    }
    _session->remove_torrent(h, deleteFiles ? lt::session_handle::delete_files : lt::remove_flags_t{});
}

- (void)pauseAll {
    for (lt::torrent_handle const &h : _session->get_torrents()) {
        h.unset_flags(lt::torrent_flags::auto_managed);
        h.pause(lt::torrent_handle::graceful_pause);
    }
}

- (void)resumeAll {
    for (lt::torrent_handle const &h : _session->get_torrents()) {
        h.set_flags(lt::torrent_flags::auto_managed);
        h.resume();
    }
}

- (void)pauseSession {
    if (_session) _session->pause();
}

- (void)resumeSession {
    if (_session) _session->resume();
}

- (BOOL)isSessionPaused {
    return _session ? _session->is_paused() : YES;
}

- (NSArray<TLTorrentStatus *> *)allStatuses {
    if (!_session) return @[];
    auto statuses = _session->get_torrent_status([](lt::torrent_status const &) { return true; },
                                                 lt::torrent_handle::query_name | lt::torrent_handle::query_save_path |
                                                     lt::torrent_handle::query_torrent_file);
    NSMutableArray<TLTorrentStatus *> *result = [NSMutableArray arrayWithCapacity:statuses.size()];
    for (auto const &st : statuses) [result addObject:TLMakeStatus(st)];
    return result;
}

- (TLTorrentStatus *)statusOf:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return nil;
    return TLMakeStatus(h.status(lt::torrent_handle::query_name | lt::torrent_handle::query_save_path |
                                 lt::torrent_handle::query_torrent_file));
}

- (NSArray<TLFileEntry *> *)filesOf:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return @[];
    auto ti = h.torrent_file();
    if (!ti) return @[];
    std::vector<std::int64_t> progress;
    h.file_progress(progress, lt::torrent_handle::piece_granularity);
    auto priorities = h.get_file_priorities();
    return TLFiles(ti->files(), &progress, &priorities);
}

- (void)setFilePriorities:(NSArray<NSNumber *> *)priorities forTorrent:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    std::vector<lt::download_priority_t> prios;
    for (NSNumber *p in priorities) prios.push_back(lt::download_priority_t{static_cast<std::uint8_t>(p.intValue)});
    h.prioritize_files(prios);
}

- (NSData *)piecesOf:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return [NSData data];
    lt::torrent_status st = h.status(lt::torrent_handle::query_pieces);
    NSMutableData *data = [NSMutableData dataWithLength:static_cast<NSUInteger>(st.pieces.size())];
    auto *bytes = static_cast<uint8_t *>(data.mutableBytes);
    for (int i = 0; i < st.pieces.size(); ++i) bytes[i] = st.pieces.get_bit(lt::piece_index_t{i}) ? 1 : 0;
    return data;
}

- (NSArray<TLTracker *> *)trackersOf:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return @[];
    NSMutableArray<TLTracker *> *result = [NSMutableArray array];
    for (lt::announce_entry const &ae : h.trackers()) {
        BOOL working = NO, updating = NO;
        int fails = 0, seeds = -1, peers = -1;
        std::string message;
        for (auto const &ep : ae.endpoints) {
            for (auto const &ih : ep.info_hashes) {
                // Listen sockets that cannot reach this tracker (e.g. IPv6 vs an IPv4-only host) report
                // "announce skipped"; they say nothing about the tracker itself.
                if (ih.last_error == lt::errors::announce_skipped) continue;
                if (ih.updating) updating = YES;
                if (ih.fails == 0 && !ih.last_error && ih.start_sent) working = YES;
                fails = MAX(fails, (int)ih.fails);
                seeds = MAX(seeds, ih.scrape_complete);
                peers = MAX(peers, ih.scrape_incomplete);
                if (message.empty()) {
                    // For a tracker failure the tracker's own reason is in `message`.
                    if (ih.last_error && !ih.message.empty()) message = ih.last_error.message() + ": " + ih.message;
                    else message = ih.last_error ? ih.last_error.message() : ih.message;
                }
            }
        }
        [result addObject:[[TLTracker alloc] initWithURL:TLString(ae.url) tier:ae.tier working:working updating:updating
                                                   fails:fails seeds:seeds peers:peers message:TLString(message)]];
    }
    return result;
}

- (void)addTracker:(NSString *)url toTorrent:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    lt::announce_entry ae(TLStd(url));
    ae.tier = static_cast<std::uint8_t>(h.trackers().size());
    h.add_tracker(ae);
}

- (void)replaceTrackers:(NSArray<NSString *> *)urls ofTorrent:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    std::vector<lt::announce_entry> entries;
    std::uint8_t tier = 0;
    for (NSString *url in urls) {
        lt::announce_entry ae(TLStd(url));
        ae.tier = tier++;
        entries.push_back(ae);
    }
    h.replace_trackers(entries);
}

- (NSString *)magnetLinkOf:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return nil;
    return TLString(lt::make_magnet_uri(h));
}

- (void)forceReannounce:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (h.is_valid()) h.force_reannounce();
}

- (void)forceDHTAnnounce:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (h.is_valid()) h.force_dht_announce();
}

- (void)forceRecheck:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (h.is_valid()) h.force_recheck();
}

- (void)setDownloadLimit:(int)downloadLimit uploadLimit:(int)uploadLimit forTorrent:(NSString *)infoHash {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (!h.is_valid()) return;
    h.set_download_limit(downloadLimit > 0 ? downloadLimit : -1);
    h.set_upload_limit(uploadLimit > 0 ? uploadLimit : -1);
}

- (void)moveStorageOf:(NSString *)infoHash to:(NSString *)path {
    lt::torrent_handle h = [self handleFor:infoHash];
    if (h.is_valid()) h.move_storage(TLStd(path));
}

- (void)saveStateWithCompletion:(void (^)(void))completion {
    if (!_session) {
        dispatch_async(dispatch_get_main_queue(), completion);
        return;
    }
    TLWriteFile([self sessionStatePath], lt::write_session_params_buf(_session->session_state(), lt::session_handle::save_dht_state));
    auto handles = _session->get_torrents();
    BOOL callNow = NO;
    {
        std::lock_guard<std::mutex> lock(_saveMutex);
        int requested = 0;
        for (auto const &h : handles) {
            if (!h.is_valid() || !h.need_save_resume_data()) continue;
            h.save_resume_data(lt::torrent_handle::save_info_dict);
            requested++;
        }
        _pendingResumeSaves += requested;
        if (_pendingResumeSaves == 0) {
            callNow = YES;
        } else {
            [_saveCompletions addObject:[completion copy]];
        }
    }
    if (callNow) dispatch_async(dispatch_get_main_queue(), completion);
}

@end
