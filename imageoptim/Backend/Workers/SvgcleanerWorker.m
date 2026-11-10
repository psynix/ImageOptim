
#import "SvgcleanerWorker.h"
#import "../Job.h"
#import "../TempFile.h"
#import "../../log.h"

static NSString *canonicalSVGAtURL(NSURL *path) {
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:path
                                                               options:NSXMLNodeLoadExternalEntitiesNever | NSXMLNodePreserveWhitespace
                                                                 error:nil];
    if (!document || ![document.rootElement.localName isEqualToString:@"svg"]) return nil;

    return [document canonicalXMLStringPreservingComments:NO];
}

@implementation SvgcleanerWorker

- (instancetype)initWithLossy:(BOOL)lossy job:(Job *)f {
    if (self = [super initWithFile:f]) {
        useLossy = lossy;
    }
    return self;
}

- (NSInteger)settingsIdentifier {
    return useLossy ? 7 : 8;
}

- (BOOL)optimizeFile:(File *)file toTempPath:(NSURL *)temp {
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:file.path
                                                               options:NSXMLNodeLoadExternalEntitiesNever | NSXMLNodePreserveWhitespace
                                                                 error:nil];
    if (!document) return NO;
    // This archived parser cannot safely rewrite CSS, scripts, HTML, or animated geometry.
    NSArray *sensitiveContent = [document nodesForXPath:@"//*[local-name()='style' or local-name()='script' or local-name()='foreignObject' or starts-with(local-name(), 'animate') or local-name()='set'] | //processing-instruction('xml-stylesheet')" error:nil];
    if (sensitiveContent.count) return NO;

    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"--stdout", @"--", file.path,
                                                            nil];

    if (!useLossy) {
        [args insertObjects:@[@"--no-defaults", @"--remove-comments=true", @"--coordinates-precision=12", @"--properties-precision=12", @"--paths-coordinates-precision=12", @"--transforms-precision=12"]
                  atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 6)]];
    } else {
        [args insertObjects:@[@"--remove-title=false", @"--remove-desc=false", @"--remove-unreferenced-ids=false", @"--trim-ids=false", @"--remove-nonsvg-attributes=false"]
                  atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 5)]];
    }

    if (![self taskForKey:@"Svgcleaner" bundleName:@"svgcleaner" arguments:args]) {
        return NO;
    }

    NSError *err = nil;
    [[NSData new] writeToURL:temp atomically:NO]; // make the file
    NSFileHandle *fileOutputHandle = [NSFileHandle fileHandleForWritingToURL:temp error:&err];

    if (!fileOutputHandle) {
        IOWarn("Can't create %@ %@", temp.path, err);
        return NO;
    }

    [task setStandardOutput:fileOutputHandle];

    NSFileHandle *devnull = [NSFileHandle fileHandleWithNullDevice];

    [task setStandardInput:devnull];
    [task setStandardError:devnull];

    [self launchTask];
    BOOL ok = [self waitUntilTaskExit];

    [devnull closeFile];
    [fileOutputHandle closeFile];

    if (!ok) return NO;

    if (!useLossy) {
        NSString *original = canonicalSVGAtURL(file.path);
        if (!original || ![original isEqualToString:canonicalSVGAtURL(temp)]) return NO;
    }

    return [job setFileOptimized:[file tempCopyOfPath:temp] toolName:@"Svgcleaner"];
}

@end
