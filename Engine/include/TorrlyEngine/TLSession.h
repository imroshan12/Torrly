#import <Foundation/Foundation.h>
#import <TorrlyEngine/TLModels.h>

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const TLErrorDomain NS_SWIFT_NAME(EngineErrorDomain);

@class TLSession;

/// Delegate callbacks arrive on the main queue.
NS_SWIFT_NAME(EngineSessionDelegate)
@protocol TLSessionDelegate <NSObject>
/// Called about once a second with every torrent in the session.
- (void)session:(TLSession *)session didUpdateTorrents:(NSArray<TLTorrentStatus *> *)torrents;
- (void)session:(TLSession *)session torrentDidFinish:(NSString *)infoHash;
- (void)session:(TLSession *)session torrentDidReceiveMetadata:(NSString *)infoHash;
- (void)session:(TLSession *)session torrent:(nullable NSString *)infoHash didFailWithMessage:(NSString *)message;
- (void)session:(TLSession *)session torrentWasRemoved:(NSString *)infoHash;
@end

/// Thread-safe wrapper around one libtorrent session.
/// Resume data and DHT state live in `stateDirectory`.
NS_SWIFT_NAME(EngineSession)
NS_SWIFT_SENDABLE
@interface TLSession : NSObject

@property (nonatomic, weak, nullable) id<TLSessionDelegate> delegate;

- (instancetype)initWithSettings:(TLSessionSettings *)settings stateDirectory:(NSString *)stateDirectory;
- (instancetype)init NS_UNAVAILABLE;

+ (NSString *)libtorrentVersion;

/// Re-adds every torrent saved in the state directory. A saved download folder outside the app's current
/// home directory (iOS moves the app container between installs) is replaced by `savePath`.
- (void)restoreTorrentsWithSavePath:(NSString *)savePath;
- (void)applySettings:(TLSessionSettings *)settings;

/// Returns the info hash (hex) of the added torrent.
- (nullable NSString *)addMagnet:(NSString *)uri savePath:(NSString *)savePath error:(NSError **)error;
/// `filePriorities` may be nil (download everything).
- (nullable NSString *)addTorrentFile:(NSString *)path savePath:(NSString *)savePath filePriorities:(nullable NSArray<NSNumber *> *)filePriorities error:(NSError **)error;
+ (nullable TLTorrentInfo *)readTorrentFile:(NSString *)path error:(NSError **)error;
/// Info hash (hex) of a magnet link, or nil if it is not a valid magnet.
+ (nullable NSString *)infoHashOfMagnet:(NSString *)uri;

- (void)pauseTorrent:(NSString *)infoHash;
- (void)resumeTorrent:(NSString *)infoHash;
- (void)removeTorrent:(NSString *)infoHash deleteFiles:(BOOL)deleteFiles;
- (void)pauseAll;
- (void)resumeAll;
/// Pauses the whole session without changing each torrent's own paused state (used for Wi-Fi only).
- (void)pauseSession NS_SWIFT_NAME(pauseSession());
- (void)resumeSession NS_SWIFT_NAME(resumeSession());
@property (nonatomic, readonly) BOOL isSessionPaused;

- (NSArray<TLTorrentStatus *> *)allStatuses;
- (nullable TLTorrentStatus *)statusOf:(NSString *)infoHash;
- (NSArray<TLFileEntry *> *)filesOf:(NSString *)infoHash;
- (void)setFilePriorities:(NSArray<NSNumber *> *)priorities forTorrent:(NSString *)infoHash;
/// One byte per piece: 1 if the piece is downloaded.
- (NSData *)piecesOf:(NSString *)infoHash;
- (NSArray<TLTracker *> *)trackersOf:(NSString *)infoHash;
- (void)addTracker:(NSString *)url toTorrent:(NSString *)infoHash;
- (void)replaceTrackers:(NSArray<NSString *> *)urls ofTorrent:(NSString *)infoHash;
- (nullable NSString *)magnetLinkOf:(NSString *)infoHash;

- (void)forceReannounce:(NSString *)infoHash;
- (void)forceDHTAnnounce:(NSString *)infoHash;
- (void)forceRecheck:(NSString *)infoHash;
- (void)setDownloadLimit:(int)downloadLimit uploadLimit:(int)uploadLimit forTorrent:(NSString *)infoHash;
- (void)moveStorageOf:(NSString *)infoHash to:(NSString *)path;

/// Writes resume data for every torrent plus DHT state; the handler runs on the main queue.
- (void)saveStateWithCompletion:(void (^ NS_SWIFT_SENDABLE)(void))completion;
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
