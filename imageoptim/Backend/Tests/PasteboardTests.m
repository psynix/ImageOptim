@import Cocoa;
#import <XCTest/XCTest.h>
#import "FilesController.h"
#import "ImageOptimController.h"
#import "DragDropImageView.h"

@interface ImageOptimController (ServicesTests)
- (void)handleServices:(NSPasteboard *)pasteboard userData:(NSString *)userData error:(NSString **)error;
@end

@interface RecordingFilesController : FilesController
@property (copy) NSArray<NSURL *> *receivedURLs;
@property (strong) XCTestExpectation *receivedFiles;
@end

@implementation RecordingFilesController
- (BOOL)addURLs:(NSArray<NSURL *> *)urls {
    self.receivedURLs = urls;
    [self.receivedFiles fulfill];
    return YES;
}
@end

@interface TestDraggingInfo : NSObject
@property (strong) NSPasteboard *draggingPasteboard;
@property (strong) id draggingSource;
@end

@implementation TestDraggingInfo
@end

@interface PasteboardTests : XCTestCase
@property (strong) NSPasteboard *pasteboard;
@property (copy) NSArray<NSURL *> *fileURLs;
@end

@implementation PasteboardTests

- (void)setUp {
    [super setUp];
    self.pasteboard = [NSPasteboard pasteboardWithUniqueName];
    self.fileURLs = @[[NSURL fileURLWithPath:@"/tmp/image with spaces #1.png"],
                      [NSURL fileURLWithPath:@"/tmp/café.jpg"]];
    XCTAssertTrue([self.pasteboard writeObjects:self.fileURLs]);
}

- (void)tearDown {
    [self.pasteboard releaseGlobally];
    [super tearDown];
}

- (void)testServicesImportsEveryFileURL {
    RecordingFilesController *files = [RecordingFilesController new];
    files.receivedFiles = [self expectationWithDescription:@"Services imported file URLs"];
    ImageOptimController *controller = [ImageOptimController new];
    [controller setValue:files forKey:@"filesController"];

    [controller handleServices:self.pasteboard userData:nil error:nil];

    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertEqualObjects(files.receivedURLs, self.fileURLs);
}

- (void)testDropZoneImportsEveryFileURL {
    RecordingFilesController *files = [RecordingFilesController new];
    files.receivedFiles = [self expectationWithDescription:@"Drop zone imported file URLs"];
    DragDropImageView *view = [DragDropImageView new];
    [view setValue:files forKey:@"filesController"];
    TestDraggingInfo *drag = [TestDraggingInfo new];
    drag.draggingPasteboard = self.pasteboard;

    XCTAssertEqual([view draggingEntered:(id<NSDraggingInfo>)drag], NSDragOperationCopy);
    XCTAssertTrue([view performDragOperation:(id<NSDraggingInfo>)drag]);

    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertEqualObjects(files.receivedURLs, self.fileURLs);
}

- (void)testTableDropImportsEveryFileURL {
    RecordingFilesController *files = [RecordingFilesController new];
    files.receivedFiles = [self expectationWithDescription:@"Table imported file URLs"];
    TestDraggingInfo *drag = [TestDraggingInfo new];
    drag.draggingPasteboard = self.pasteboard;

    XCTAssertTrue([files tableView:[NSTableView new] acceptDrop:(id<NSDraggingInfo>)drag
                              row:0 dropOperation:NSTableViewDropAbove]);

    [self waitForExpectationsWithTimeout:2 handler:nil];
    XCTAssertEqualObjects(files.receivedURLs, self.fileURLs);
}

- (void)testDropZoneRejectsWebURLs {
    [self.pasteboard clearContents];
    XCTAssertTrue([self.pasteboard writeObjects:@[[NSURL URLWithString:@"https://example.com/image.png"]]]);
    DragDropImageView *view = [DragDropImageView new];
    TestDraggingInfo *drag = [TestDraggingInfo new];
    drag.draggingPasteboard = self.pasteboard;

    XCTAssertEqual([view draggingEntered:(id<NSDraggingInfo>)drag], NSDragOperationNone);
    XCTAssertFalse([view performDragOperation:(id<NSDraggingInfo>)drag]);
}

- (void)testDraggingRowsPublishesEveryFileURL {
    FilesController *files = [FilesController new];
    files.content = @[@{@"filePath": self.fileURLs[0]}, @{@"filePath": self.fileURLs[1]}];
    [files setValue:@YES forKey:@"isEnabled"];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    XCTAssertTrue([files tableView:[NSTableView new] writeRowsWithIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]
                      toPasteboard:self.pasteboard]);
#pragma clang diagnostic pop

    NSArray *urls = [self.pasteboard readObjectsForClasses:@[[NSURL class]]
                                                  options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    XCTAssertEqualObjects(urls, self.fileURLs);
    XCTAssertNotNil([self.pasteboard dataForType:@"com.imageoptim.rows"]);
}

@end
