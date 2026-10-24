#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TLTorrentState) {
    TLTorrentStateCheckingFiles = 0,
    TLTorrentStateDownloadingMetadata,
    TLTorrentStateDownloading,
    TLTorrentStateFinished,
    TLTorrentStateSeeding,
    TLTorrentStateCheckingResumeData,
    TLTorrentStatePaused,
    TLTorrentStateError,
} NS_SWIFT_NAME(EngineTorrentState);

typedef NS_ENUM(NSInteger, TLEncryptionPolicy) {
    TLEncryptionPolicyForced = 0,
    TLEncryptionPolicyPrefer,
    TLEncryptionPolicyDisabled,
} NS_SWIFT_NAME(EngineEncryptionPolicy);

typedef NS_ENUM(NSInteger, TLProxyType) {
    TLProxyTypeNone = 0,
    TLProxyTypeSocks4,
    TLProxyTypeSocks5,
    TLProxyTypeHTTP,
} NS_SWIFT_NAME(EngineProxyType);

/// Session-wide settings. Rates are bytes per second; 0 means unlimited.
NS_SWIFT_NAME(EngineSettings)
@interface TLSessionSettings : NSObject <NSCopying>
@property (nonatomic) int listenPort;
@property (nonatomic) int maxDownloadRate;
@property (nonatomic) int maxUploadRate;
@property (nonatomic) TLEncryptionPolicy incomingEncryption;
@property (nonatomic) TLEncryptionPolicy outgoingEncryption;
@property (nonatomic) BOOL dhtEnabled;
@property (nonatomic) TLProxyType proxyType;
@property (nonatomic, copy) NSString *proxyHost;
@property (nonatomic) int proxyPort;
@property (nonatomic, copy) NSString *proxyUsername;
@property (nonatomic, copy) NSString *proxyPassword;
/// PEM file of trusted CAs for HTTPS trackers and web seeds (iOS has no OpenSSL certificate store).
@property (nonatomic, copy, nullable) NSString *caBundlePath;
@end

/// Immutable snapshot of one torrent.
NS_SWIFT_NAME(EngineTorrentStatus)
NS_SWIFT_SENDABLE
@interface TLTorrentStatus : NSObject
@property (nonatomic, readonly, copy) NSString *infoHash;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *savePath;
@property (nonatomic, readonly) TLTorrentState state;
@property (nonatomic, readonly) BOOL isPaused;
@property (nonatomic, readonly) BOOL hasMetadata;
@property (nonatomic, readonly) float progress;
@property (nonatomic, readonly) int64_t totalWanted;
@property (nonatomic, readonly) int64_t totalWantedDone;
@property (nonatomic, readonly) int64_t totalUploaded;
@property (nonatomic, readonly) int64_t totalDownloaded;
@property (nonatomic, readonly) int downloadRate;
@property (nonatomic, readonly) int uploadRate;
@property (nonatomic, readonly) int connectedSeeds;
@property (nonatomic, readonly) int connectedPeers;
@property (nonatomic, readonly) int totalSeeds;
@property (nonatomic, readonly) int totalPeers;
@property (nonatomic, readonly) int numPieces;
@property (nonatomic, readonly) int pieceLength;
@property (nonatomic, readonly) int downloadLimit;
@property (nonatomic, readonly) int uploadLimit;
@property (nonatomic, readonly, copy, nullable) NSString *errorMessage;
@property (nonatomic, readonly) NSDate *addedDate;
@property (nonatomic, readonly, nullable) NSDate *completedDate;
@end

NS_SWIFT_NAME(EngineFile)
NS_SWIFT_SENDABLE
@interface TLFileEntry : NSObject
@property (nonatomic, readonly) int index;
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly) int64_t size;
@property (nonatomic, readonly) int64_t downloaded;
/// 0 = skip, 1...7 = libtorrent priority (4 is normal).
@property (nonatomic, readonly) int priority;
@end

NS_SWIFT_NAME(EngineTracker)
NS_SWIFT_SENDABLE
@interface TLTracker : NSObject
@property (nonatomic, readonly, copy) NSString *url;
@property (nonatomic, readonly) int tier;
@property (nonatomic, readonly) BOOL working;
@property (nonatomic, readonly) BOOL updating;
@property (nonatomic, readonly) int fails;
@property (nonatomic, readonly) int seeds;
@property (nonatomic, readonly) int peers;
@property (nonatomic, readonly, copy) NSString *message;
@end

/// Metadata read from a .torrent file before it is added.
NS_SWIFT_NAME(EngineTorrentInfo)
NS_SWIFT_SENDABLE
@interface TLTorrentInfo : NSObject
@property (nonatomic, readonly, copy) NSString *infoHash;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) int64_t totalSize;
@property (nonatomic, readonly) int numPieces;
@property (nonatomic, readonly, copy) NSArray<TLFileEntry *> *files;
@property (nonatomic, readonly, copy) NSArray<NSString *> *trackers;
@end

NS_ASSUME_NONNULL_END
