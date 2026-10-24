#import "TLModels+Internal.h"

@implementation TLSessionSettings

- (instancetype)init {
    if ((self = [super init])) {
        _listenPort = 0;
        _incomingEncryption = TLEncryptionPolicyPrefer;
        _outgoingEncryption = TLEncryptionPolicyPrefer;
        _dhtEnabled = YES;
        _proxyType = TLProxyTypeNone;
        _proxyHost = @"";
        _proxyUsername = @"";
        _proxyPassword = @"";
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    TLSessionSettings *copy = [[TLSessionSettings allocWithZone:zone] init];
    copy.listenPort = _listenPort;
    copy.maxDownloadRate = _maxDownloadRate;
    copy.maxUploadRate = _maxUploadRate;
    copy.incomingEncryption = _incomingEncryption;
    copy.outgoingEncryption = _outgoingEncryption;
    copy.dhtEnabled = _dhtEnabled;
    copy.proxyType = _proxyType;
    copy.proxyHost = _proxyHost;
    copy.proxyPort = _proxyPort;
    copy.proxyUsername = _proxyUsername;
    copy.proxyPassword = _proxyPassword;
    copy.caBundlePath = _caBundlePath;
    return copy;
}

@end

@implementation TLTorrentStatus
@end

@implementation TLFileEntry

- (instancetype)initWithIndex:(int)index path:(NSString *)path size:(int64_t)size downloaded:(int64_t)downloaded priority:(int)priority {
    if ((self = [super init])) {
        _index = index;
        _path = [path copy];
        _size = size;
        _downloaded = downloaded;
        _priority = priority;
    }
    return self;
}

@end

@implementation TLTracker

- (instancetype)initWithURL:(NSString *)url tier:(int)tier working:(BOOL)working updating:(BOOL)updating fails:(int)fails seeds:(int)seeds peers:(int)peers message:(NSString *)message {
    if ((self = [super init])) {
        _url = [url copy];
        _tier = tier;
        _working = working;
        _updating = updating;
        _fails = fails;
        _seeds = seeds;
        _peers = peers;
        _message = [message copy];
    }
    return self;
}

@end

@implementation TLTorrentInfo

- (instancetype)initWithInfoHash:(NSString *)infoHash name:(NSString *)name totalSize:(int64_t)totalSize numPieces:(int)numPieces files:(NSArray<TLFileEntry *> *)files trackers:(NSArray<NSString *> *)trackers {
    if ((self = [super init])) {
        _infoHash = [infoHash copy];
        _name = [name copy];
        _totalSize = totalSize;
        _numPieces = numPieces;
        _files = [files copy];
        _trackers = [trackers copy];
    }
    return self;
}

@end
