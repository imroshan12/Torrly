#import <TorrlyEngine/TLModels.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLTorrentStatus ()
@property (nonatomic, readwrite, copy) NSString *infoHash;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *savePath;
@property (nonatomic, readwrite) TLTorrentState state;
@property (nonatomic, readwrite) BOOL isPaused;
@property (nonatomic, readwrite) BOOL hasMetadata;
@property (nonatomic, readwrite) float progress;
@property (nonatomic, readwrite) int64_t totalWanted;
@property (nonatomic, readwrite) int64_t totalWantedDone;
@property (nonatomic, readwrite) int64_t totalUploaded;
@property (nonatomic, readwrite) int64_t totalDownloaded;
@property (nonatomic, readwrite) int downloadRate;
@property (nonatomic, readwrite) int uploadRate;
@property (nonatomic, readwrite) int connectedSeeds;
@property (nonatomic, readwrite) int connectedPeers;
@property (nonatomic, readwrite) int totalSeeds;
@property (nonatomic, readwrite) int totalPeers;
@property (nonatomic, readwrite) int numPieces;
@property (nonatomic, readwrite) int pieceLength;
@property (nonatomic, readwrite) int downloadLimit;
@property (nonatomic, readwrite) int uploadLimit;
@property (nonatomic, readwrite, copy, nullable) NSString *errorMessage;
@property (nonatomic, readwrite) NSDate *addedDate;
@property (nonatomic, readwrite, nullable) NSDate *completedDate;
@end

@interface TLFileEntry ()
- (instancetype)initWithIndex:(int)index path:(NSString *)path size:(int64_t)size downloaded:(int64_t)downloaded priority:(int)priority;
@end

@interface TLTracker ()
- (instancetype)initWithURL:(NSString *)url tier:(int)tier working:(BOOL)working updating:(BOOL)updating fails:(int)fails seeds:(int)seeds peers:(int)peers message:(NSString *)message;
@end

@interface TLTorrentInfo ()
- (instancetype)initWithInfoHash:(NSString *)infoHash name:(NSString *)name totalSize:(int64_t)totalSize numPieces:(int)numPieces files:(NSArray<TLFileEntry *> *)files trackers:(NSArray<NSString *> *)trackers;
@end

NS_ASSUME_NONNULL_END
