@import Cocoa;
#import <XCTest/XCTest.h>
#import "Job.h"
#import "File.h"
#import "SvgcleanerWorker.h"
#import "SvgoWorker.h"

@interface Job (SVGTests)
- (void)setNewFileInitial:(File *)file;
@end

@interface SvgoWorker (SVGTests)
- (NSString *)nodePath;
@end

@interface SVGTests : XCTestCase
@end

@implementation SVGTests

- (void)testSvgcleanerRejectsRoundedGeometryInLosslessMode {
    NSString *svg = @"<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1 1\"><!-- removable padding padding padding padding --><rect x=\"0.12345678901234567\" y=\"0\" width=\"0.54321098765432109\" height=\"1\" fill=\"#ff0000\"/></svg>";
    [self checkSvgcleaner:svg lossy:NO mustKeepOriginal:YES];
}

- (void)testSvgcleanerPreservesTextWhitespaceAndAccessibility {
    NSString *svg = @"<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 96 64\" role=\"img\" aria-labelledby=\"label\"><title id=\"label\">Accessible image</title><desc>Description</desc><text xml:space=\"preserve\" x=\"0\" y=\"20\">A<tspan>B</tspan> <tspan>C</tspan></text></svg>";
    [self checkSvgcleaner:svg lossy:NO mustKeepOriginal:NO];
}

- (void)testSvgcleanerRejectsObservableWhitespaceChanges {
    NSString *svg = @"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"96\" height=\"64\"><style>rect { fill: red; } g:empty + rect { fill: blue; }</style><g id=\"observer\"> </g><rect width=\"96\" height=\"64\"/></svg>";
    [self checkSvgcleaner:svg lossy:NO mustKeepOriginal:YES];
}

- (void)testSvgcleanerPreservesPathMorphingCommands {
    NSString *svg = @"<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 96 64\"><path d=\"M 4 4 L 84 4 L 44 54 Z\"><animate attributeName=\"d\" values=\"M 4 4 L 84 4 L 44 54 Z;M 14 14 L 74 14 L 44 44 Z\" dur=\"3s\"/></path></svg>";
    [self checkSvgcleaner:svg lossy:NO mustKeepOriginal:YES];
    [self checkSvgcleaner:svg lossy:YES mustKeepOriginal:YES];
}

- (void)testSvgcleanerStillCompressesLexicalContent {
    NSString *svg = @"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"32\"><!-- removable padding padding padding padding padding padding padding padding --><rect width=\"32\" height=\"32\" fill=\"#ff0000\"/></svg>";
    Job *job = [self checkSvgcleaner:svg lossy:NO mustKeepOriginal:NO];
    XCTAssertLessThan(job.wipInput.byteSize, [svg lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
}

- (void)testSvgoDiscoversExecutableOnPATH {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSFileManager *manager = [NSFileManager defaultManager];
    XCTAssertTrue([manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]);
    NSString *node = [directory stringByAppendingPathComponent:@"node"];
    XCTAssertTrue([@"#!/bin/sh\nexit 0\n" writeToFile:node atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    XCTAssertTrue([manager setAttributes:@{NSFilePosixPermissions: @0700} ofItemAtPath:node error:nil]);
    NSString *previous = [NSProcessInfo processInfo].environment[@"PATH"];
    @try {
        setenv("PATH", directory.fileSystemRepresentation, 1);
        Job *job = [[Job alloc] initWithFilePath:[NSURL fileURLWithPath:@"/tmp/unused.svg"] resultsDatabase:nil];
        SvgoWorker *worker = [[SvgoWorker alloc] initWithLossy:NO job:job];
        XCTAssertEqualObjects([worker nodePath], node);
    } @finally {
        if (previous) setenv("PATH", previous.UTF8String, 1); else unsetenv("PATH");
        [manager removeItemAtPath:directory error:nil];
    }
}

- (Job *)checkSvgcleaner:(NSString *)svg lossy:(BOOL)lossy mustKeepOriginal:(BOOL)mustKeepOriginal {
    NSData *original = [svg dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *path = [NSURL fileURLWithPath:[[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString] stringByAppendingPathExtension:@"svg"]];
    XCTAssertTrue([original writeToURL:path atomically:YES]);
    File *input = [[File alloc] initWithData:original fromPath:path];
    Job *job = [[Job alloc] initWithFilePath:path resultsDatabase:nil];
    [job setNewFileInitial:input];
    SvgcleanerWorker *worker = [[SvgcleanerWorker alloc] initWithLossy:lossy job:job];
    [worker run];
    if (mustKeepOriginal) XCTAssertEqual(job.wipInput, input);
    NSData *result = [NSData dataWithContentsOfURL:job.wipInput.path];
    NSXMLDocument *before = [[NSXMLDocument alloc] initWithData:original options:NSXMLNodeLoadExternalEntitiesNever | NSXMLNodePreserveWhitespace error:nil];
    NSXMLDocument *after = [[NSXMLDocument alloc] initWithData:result options:NSXMLNodeLoadExternalEntitiesNever | NSXMLNodePreserveWhitespace error:nil];
    XCTAssertNotNil(before);
    XCTAssertNotNil(after);
    XCTAssertEqualObjects([before canonicalXMLStringPreservingComments:NO], [after canonicalXMLStringPreservingComments:NO]);
    [[NSFileManager defaultManager] removeItemAtURL:path error:nil];
    return job;
}

@end
