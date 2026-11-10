//
//  BackendTests.m
//  BackendTests
//
//  Created by Kornel on 20/04/2015.
//
//

@import Cocoa;
#import <XCTest/XCTest.h>
#import "Job.h"
#import "JobQueue.h"
#import "File.h"
#import "TempFile.h"
#import "CommandWorker.h"

@interface Job (CacheTests)
- (void)setSettingsHash:(NSArray *)allWorkers;
- (void)setNewFileInitial:(File *)initial;
- (void)saveResultAndUpdateStatus;
@end

@interface CacheTestJob : Job
- (NSData *)settingsHashForWorkers:(NSArray *)allWorkers;
- (void)prepareForSave;
@end

@implementation CacheTestJob
- (NSData *)settingsHashForWorkers:(NSArray *)allWorkers {
    [self setSettingsHash:allWorkers];
    return [NSData dataWithBytes:settingsHash length:sizeof(settingsHash)];
}
- (void)prepareForSave {
    workers = [NSMutableArray arrayWithObject:[NSOperation new]];
}
@end

@interface RecordingResultsDb : NSObject
@property NSUInteger writeCount;
- (void)setUnoptimizableFileHash:(uint32_t *)hash size:(NSUInteger)size;
@end
@implementation RecordingResultsDb
- (void)setUnoptimizableFileHash:(uint32_t *)hash size:(NSUInteger)size {
    self.writeCount++;
}
@end

@interface CountingWorker : Worker
@property NSUInteger runCount;
@property File *replacementInput;
@end

@implementation CountingWorker
- (NSInteger)settingsIdentifier { return 1; }
- (void)run {
    self.runCount++;
    if (self.replacementInput) {
        [self.job setValue:self.replacementInput forKey:@"wipInput"];
    }
}
@end

@interface OtherCountingWorker : CountingWorker
@end
@implementation OtherCountingWorker
@end

@interface CancellingCommandWorker : CommandWorker
@end

@implementation CancellingCommandWorker
- (BOOL)optimizeFile:(File *)file toTempPath:(NSURL *)temp {
    if (![[NSData dataWithBytes:"adopted output" length:14] writeToURL:temp atomically:NO]) {
        return NO;
    }
    BOOL adopted = [self.job setFileOptimized:[file tempCopyOfPath:temp] toolName:@"Test"];
    [self cancel];
    return adopted;
}
@end

@interface BackendTests : XCTestCase

@end

@implementation BackendTests

- (File *)inputFile {
    NSURL *path = [[NSBundle bundleForClass:[self class]] URLForResource:@"unoptimized" withExtension:@"png"];
    return [[File alloc] initWithData:[NSData dataWithContentsOfURL:path] fromPath:path];
}

- (void)testWorkerDoesNotCacheInputReplacedDuringRun {
    File *input = [self inputFile];
    Job *job = [[Job alloc] initWithFilePath:input.path resultsDatabase:nil];
    [job setNewFileInitial:input];

    CountingWorker *first = [[CountingWorker alloc] initWithFile:job];
    first.replacementInput = [input copyOfPath:input.path size:input.byteSize / 2];
    [first start];
    XCTAssertEqual(first.runCount, 1U);

    CountingWorker *second = [[CountingWorker alloc] initWithFile:job];
    [second start];
    XCTAssertEqual(second.runCount, 1U);

    CountingWorker *third = [[CountingWorker alloc] initWithFile:job];
    [third start];
    XCTAssertEqual(third.runCount, 0U);
}

- (void)testCancellationKeepsAdoptedTemporaryFile {
    File *input = [self inputFile];
    Job *job = [[Job alloc] initWithFilePath:input.path resultsDatabase:nil];
    [job setNewFileInitial:input];
    CancellingCommandWorker *worker = [[CancellingCommandWorker alloc] initWithFile:job];
    [worker run];

    XCTAssertTrue(worker.isCancelled);
    XCTAssertNotEqual(job.wipInput, input);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:job.wipInput.path.path]);
    [[NSFileManager defaultManager] removeItemAtURL:job.wipInput.path error:nil];
}

- (void)testSettingsHashIncludesWorkerIdentity {
    CacheTestJob *job = [[CacheTestJob alloc] initWithFilePath:[self inputFile].path resultsDatabase:nil];
    CountingWorker *first = [[CountingWorker alloc] initWithFile:job];
    OtherCountingWorker *second = [[OtherCountingWorker alloc] initWithFile:job];
    XCTAssertEqual(first.settingsIdentifier, second.settingsIdentifier);
    XCTAssertNotEqualObjects([job settingsHashForWorkers:@[first]], [job settingsHashForWorkers:@[second]]);
}

- (void)testReplacingInitialInputClearsWorkerCache {
    File *input = [self inputFile];
    Job *job = [[Job alloc] initWithFilePath:input.path resultsDatabase:nil];
    job.workersPreviousResults[@"CountingWorker"] = [@{@1: @(input.byteSize)} mutableCopy];
    [job setNewFileInitial:input];
    XCTAssertEqual(job.workersPreviousResults.count, 0U);
}

- (void)testNewOptimizationRequestClearsWorkerCache {
    File *input = [self inputFile];
    Job *job = [[Job alloc] initWithFilePath:input.path resultsDatabase:nil];
    job.workersPreviousResults[@"CountingWorker"] = [@{@1: @(input.byteSize)} mutableCopy];
    NSOperationQueue *cpuQueue = [NSOperationQueue new];
    NSOperationQueue *ioQueue = [NSOperationQueue new];
    ioQueue.suspended = YES;

    [job enqueueWorkersInCPUQueue:cpuQueue fileIOQueue:ioQueue
                     serialQueue:dispatch_queue_create("cache test", DISPATCH_QUEUE_SERIAL)
                        defaults:[NSUserDefaults standardUserDefaults]];
    XCTAssertEqual(job.workersPreviousResults.count, 0U);
    [job cleanup];
    ioQueue.suspended = NO;
    [ioQueue waitUntilAllOperationsAreFinished];
}

- (void)testCancelledJobDoesNotCacheFileAsUnoptimizable {
    File *input = [self inputFile];
    RecordingResultsDb *database = [RecordingResultsDb new];
    CacheTestJob *job = [[CacheTestJob alloc] initWithFilePath:input.path resultsDatabase:(ResultsDb *)database];
    [job setNewFileInitial:input];
    [job prepareForSave];
    XCTAssertTrue([job stop]);
    [job saveResultAndUpdateStatus];
    XCTAssertTrue(job.isDone);
    XCTAssertEqual(database.writeCount, 0U);

    CacheTestJob *completedJob = [[CacheTestJob alloc] initWithFilePath:input.path resultsDatabase:(ResultsDb *)database];
    [completedJob setNewFileInitial:input];
    [completedJob prepareForSave];
    [completedJob saveResultAndUpdateStatus];
    XCTAssertEqual(database.writeCount, 1U);
}

- (void)testCompressOne {
    NSURL *origPath = [[NSBundle bundleForClass:[self class]] URLForResource:@"unoptimized" withExtension:@"png"];
    NSURL *path = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]]];

    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertTrue([fm copyItemAtURL:origPath toURL:path error:nil]);

    Job *f = [[Job alloc] initWithFilePath:path resultsDatabase:nil];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:[NSUUID UUID].UUIDString];
    [defaults registerDefaults:[NSDictionary dictionaryWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"defaults" withExtension:@"plist"]]];
    JobQueue *q = [[JobQueue alloc] initWithCPUs:4
                                            dirs:1
                                           files:4
                                        defaults:defaults];

    [q addJob:f];
    XCTAssertTrue([f isBusy]);
    XCTAssertFalse([f isDone]);
    XCTAssertFalse([f isFailed]);
    [q wait];
    XCTAssertFalse([f isBusy]);

    NSNumber *size, *origSize;
    [path removeAllCachedResourceValues];
    [origPath removeAllCachedResourceValues];

    XCTAssertTrue([path getResourceValue:&size forKey:NSURLFileSizeKey error:nil]);
    XCTAssertTrue([origPath getResourceValue:&origSize forKey:NSURLFileSizeKey error:nil]);

    XCTAssertTrue([f isDone]);
    XCTAssertFalse([f isFailed]);
    XCTAssertFalse([f isStoppable]);

    XCTAssertLessThan([size integerValue], [origSize integerValue]);
    XCTAssertLessThanOrEqual([size integerValue], 5552);

    XCTAssertTrue([f canRevert]);

    XCTAssertEqual([[f byteSizeOptimized] integerValue], [size integerValue]);
    XCTAssertEqual([[f byteSizeOriginal] integerValue], [origSize integerValue]);

    [fm removeItemAtURL:path error:nil];
    if (f.revertFile) [fm removeItemAtURL:f.revertFile.path error:nil];
}

@end
