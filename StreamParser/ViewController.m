//
//  ViewController.m
//  StreamParser
//
//  Created by K, Santhosh on 01/03/17.
//  Copyright © 2017 K, Santhosh. All rights reserved.
//

#import "ViewController.h"
#import "SCTE-Marker.h"
#import "SegmentInfo.h"

static NSString * const masterPrefix    = @"#EXTM3U";
static NSString * const bitratePrefix   = @"#EXT-X-STREAM-INF:";
static NSString * const bitrateKeyword  = @"BANDWIDTH";
static NSString * const cryptPrefix     = @"#EXT-X-KEY:";
static NSString * const chunkPrefix     = @"#EXTINF:";


@interface ViewController ()

@property (strong, nonatomic) NSString *urlString;
@property (strong, nonatomic) NSMutableArray *indexPlaylists;

@property (strong, nonnull) NSMutableDictionary *markersListDict;


////////////////

@property (strong, nonatomic) NSMutableArray *primaryPlaylist;
@property (strong, nonatomic) NSMutableArray *secondaryPlaylist;

@property (strong, nonatomic) NSMutableArray *availableBitrates;



/////////////////

@property (strong, nonatomic) NSMutableDictionary *segmentsListDict;


@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.markersListDict = [NSMutableDictionary dictionary];
    self.segmentsListDict = [NSMutableDictionary dictionary];
    
    // Do any additional setup after loading the view.
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}


#pragma mark - Action methods

- (IBAction)didTapProcessButton:(id)sender {
    NSString *urlString = [self.urlTextField stringValue];
    urlString = [urlString stringByReplacingOccurrencesOfString:@" " withString:@""];
    if (!urlString.length) {
        return;
    }
    
    [self.progressIndicator startAnimation:self];
    self.label.hidden = NO;
    self.processButton.enabled = NO;
    
    self.urlString = urlString;
    [self fetchMasterManifestWithCompletionHandler:^(NSData *data) {
        self.indexPlaylists = [self indexURLsFromMasterData:data];
        
        dispatch_group_t playListGroup = dispatch_group_create();
        
        for (NSString *playlist in self.indexPlaylists) {
            dispatch_group_enter(playListGroup);
            [self fetchIndexPlaylist:playlist WithCompletionHandler:^(NSArray *markersArray) {
                dispatch_group_leave(playListGroup);
            }];
        }
        
        __weak typeof(self) weakSelf = self;
        
        dispatch_group_notify(playListGroup, dispatch_get_main_queue(), ^{
           
            [weakSelf createHtmlFile];
            [weakSelf createHtmlFileForSegments];
            [self.progressIndicator stopAnimation:self];
            self.label.hidden = YES;
            self.processButton.enabled = YES;
        });
    }];
}

#pragma mark - manifest fetching

- (void)fetchMasterManifestWithCompletionHandler:(void(^)(NSData *data))completionHandler {
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURL *url = [NSURL URLWithString:self.urlString];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        completionHandler(data);
        
    }];
    
    [task resume];
                             
}

- (void)fetchIndexPlaylist:(NSString *)playlist WithCompletionHandler:(void(^)(NSArray *markersArray))completionHandler {
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURL *url = [NSURL URLWithString:playlist];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        NSString *manifestText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"playlist url %@",playlist);
        [self parseIndexPlaylistText:manifestText ofPlaylist:playlist];
        [self parseIndexPlaylistForSegmentsInText:manifestText ofPlaylist:playlist];
        completionHandler(nil);
    }];
    
    [task resume];

}

- (void)parseIndexPlaylistText:(NSString *)text ofPlaylist:(NSString *)playlist
{
    NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    float time = 0;
    NSInteger index = 0;
    NSMutableArray *markers = [NSMutableArray array];
    for (NSString *text in lines) {
        if ([text hasPrefix:@"#EXTINF:"]) {
            NSString *duration = [text stringByReplacingOccurrencesOfString:@"#EXTINF:" withString:@""];
            time += duration.floatValue;
        } else if ([text hasPrefix:@"#EXT-X-ASSET:"]) {
            
            NSString *caId = [text stringByReplacingOccurrencesOfString:@"#EXT-X-ASSET:CAID=" withString:@""];
            int i = 0;
            NSMutableString * newCaid = [[NSMutableString alloc] init];
            while (i < [caId length]) {
                NSString * hexChar = [caId substringWithRange: NSMakeRange(i, 2)];
                int value = 0;
                sscanf([hexChar cStringUsingEncoding:NSASCIIStringEncoding], "%x", &value);
                [newCaid appendFormat:@"%c", (char)value];
                i+=2;
            }
            NSString *marker = [NSString stringWithFormat:@"%ld%@",(long)index,newCaid];
            SCTEMarker *markerSCTE = [SCTEMarker new];
            markerSCTE.markerName = marker;
            markerSCTE.time = [NSNumber numberWithFloat:time];
            [markers addObject:markerSCTE];
            index++;
        }
    }
    [self.markersListDict setObject:markers forKey:playlist];
}

- (NSMutableArray *)indexURLsFromMasterData:(NSData *)data
{
    NSString *masterText = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    masterText = [masterText stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    
    NSMutableArray *bitrateURLs = [NSMutableArray array];
    self.primaryPlaylist = [NSMutableArray array];
    self.secondaryPlaylist = [NSMutableArray array];
    self.availableBitrates = [NSMutableArray array];
    
    NSArray *lines = [masterText componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSInteger idx = 0; idx < lines.count; idx++) {
        NSString *line = lines[idx];
        if ([line hasPrefix:bitratePrefix]) {
            line = [line substringFromIndex:bitratePrefix.length];
            
            NSCharacterSet *divider = [NSCharacterSet characterSetWithCharactersInString:@",="];
            NSArray *infoArray = [line componentsSeparatedByCharactersInSet:divider];
            NSString *bitrate = nil;
            for (NSInteger jdx = 0; jdx < infoArray.count-1; jdx++) {
                if ([infoArray[jdx] isEqualToString:bitrateKeyword]) {
                    bitrate = infoArray[jdx+1];
                    break;
                }
            }
            
            
            BOOL isPrimary = YES;
            for (NSString *bRate in self.availableBitrates) {
                if ([bitrate isEqualToString:bRate]) {
                    isPrimary = NO;
                    break;
                }
            }
            NSString *url = lines[idx+1];
            [bitrateURLs addObject:url];
            if (isPrimary) {
                [self.availableBitrates addObject:bitrate];
                if ([url rangeOfString:@"-b/"].location != NSNotFound) {
                    isPrimary = NO;
                }
            }
            
            if (isPrimary) {
                [self.primaryPlaylist addObject:url];
            } else {
                [self.secondaryPlaylist addObject:url];
            }
            
            idx++;
        }
    }
    return bitrateURLs;
}

#pragma mark - 

- (void)createHtmlFile
{
    NSMutableString *tags = [[NSMutableString alloc] initWithString:@"<!DOCTYPE html><html><body><table>"];
    
    NSMutableArray *allPlaylists = [self.primaryPlaylist mutableCopy];
    [allPlaylists addObjectsFromArray:self.secondaryPlaylist];
    
    NSString *playlist = allPlaylists.firstObject;
    NSMutableArray *refMarkers = [self.markersListDict objectForKey:playlist];
    [tags appendString:@"<th>"];
    [tags appendString:@"CAID"];
    [tags appendString:@"</th>"];
    [tags appendString:@"<th> Result </th>"];
    
    for (NSString *pList in self.primaryPlaylist) {
        NSURL *url = [NSURL URLWithString:pList];
        NSString *lastComponent = url.lastPathComponent;
        lastComponent = [lastComponent stringByReplacingOccurrencesOfString:@".m3u8" withString:@""];
        [tags appendString:@"<th>"];
        [tags appendString:lastComponent];
        [tags appendString:@"</th>"];
    }
    
    [tags appendString:@"<th></th>"];

    for (NSString *pList in self.secondaryPlaylist) {
        NSURL *url = [NSURL URLWithString:pList];
        NSString *lastComponent = url.lastPathComponent;
        [tags appendString:@"<th>"];
        lastComponent = [lastComponent stringByReplacingOccurrencesOfString:@".m3u8" withString:@""];
        [tags appendString:[NSString stringWithFormat:@"(b)-%@",lastComponent]];
        [tags appendString:@"</th>"];
    }
    
    for (int i = 0; i < refMarkers.count; i++) {
        
        SCTEMarker *marker = refMarkers[i];

        [tags appendString:@"<tr>"];
        
        //marker.markerName
        [tags appendString:@"<td bgcolor = yellow>"];
        [tags appendString:[NSString stringWithFormat:@"%@",marker.markerName]];
        [tags appendString:@"</td>"];

        
        NSString *playlist = self.secondaryPlaylist.firstObject;
        
        BOOL isPrimaryStreamEqual = YES;
        BOOL isSecondaryStreamEqual = YES;
        SCTEMarker *marker2;
        
        isPrimaryStreamEqual= [self isMarkersAreEqualIn:self.primaryPlaylist marker:marker];
        if (playlist) {
            NSMutableArray *refMarkersOnSecondaryStream = [self.markersListDict objectForKey:playlist];
            if (refMarkersOnSecondaryStream.count > i) {
               marker2 = [refMarkersOnSecondaryStream objectAtIndex:i];
               isSecondaryStreamEqual = [self isMarkersAreEqualIn:self.secondaryPlaylist marker:marker2];
            }
        }

        BOOL isEqual = (isPrimaryStreamEqual && isSecondaryStreamEqual);
        if (isEqual) {
            if (marker2) {
                if (marker.time.integerValue != marker2.time.integerValue) {
                    isEqual = NO;
                }
            }
        }
        
        [tags appendString:[NSString stringWithFormat:@"<td bgcolor = %@></td>",isEqual ? @"green" : @"red"]];
        
        NSMutableString *tag = [self tagsFromPlaylist:self.primaryPlaylist forMarker:marker isEqual:isPrimaryStreamEqual];
        [tags appendString:tag];
        
        [tags appendString:@"<td></td>"];
        
        tag = [self tagsFromPlaylist:self.secondaryPlaylist forMarker:marker2 isEqual:isSecondaryStreamEqual];
        [tags appendString:tag];

        [tags appendString:@"</tr>"];
    }
    [tags appendString:@"</table></body></html>"];
    

    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
    NSString *path = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"markers"];
    NSError *error;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])    //Does directory already exist?
    {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:path
                                       withIntermediateDirectories:NO
                                                        attributes:nil
                                                             error:&error])
        {
            NSLog(@"Create directory error: %@", error);
        }
    }
    NSTimeInterval interval = [[NSDate date] timeIntervalSince1970];
    path = [path stringByAppendingString:[NSString stringWithFormat:@"/markers_%f.html",interval]];
    NSError *err ;
    [tags writeToFile:path atomically:yearMask encoding:NSUTF8StringEncoding error:&err];
}


- (BOOL)isMarkersAreEqualIn:(NSArray *)playlists marker:(SCTEMarker *)marker
{
    BOOL isEqual = YES;
    
    for (NSArray *iPlaylist in playlists) {
        NSMutableArray *markers = [self.markersListDict objectForKey:iPlaylist];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"markerName = %@", marker.markerName];
        NSArray *matchingMarkers = [markers filteredArrayUsingPredicate:predicate];
        if (matchingMarkers.count) {
            SCTEMarker *matchingMarker = matchingMarkers.firstObject;
            NSInteger markerTime1 = marker.time.integerValue;
            NSInteger markerTime2 = matchingMarker.time.integerValue;
            if (isEqual) {
                isEqual = (markerTime1 == markerTime2);
            }
        } else {
            isEqual = NO;
        }
    }
    return isEqual;
}

- (NSMutableString *)tagsFromPlaylist:(NSMutableArray *)playlists forMarker:(SCTEMarker *)marker isEqual:(BOOL)equal
{
    NSMutableString *tags = [NSMutableString new];
    for (NSArray *iPlaylist in playlists) {
        [tags appendString:[NSString stringWithFormat:@"<td bgcolor = %@>",equal ? @"green" : @"red"]];
        
        NSMutableArray *markers = [self.markersListDict objectForKey:iPlaylist];
        
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"markerName = %@", marker.markerName];
        NSArray *matchingMarkers = [markers filteredArrayUsingPredicate:predicate];
        
        if (matchingMarkers.count) {
            SCTEMarker *matchingMarker = matchingMarkers.firstObject;
            [tags appendString:[NSString stringWithFormat:@"%f",matchingMarker.time.floatValue]];
        }
        [tags appendString:@"</td>"];
    }
    
    return tags;
}

#pragma mark - Segment comparison

- (void)parseIndexPlaylistForSegmentsInText:(NSString *)text ofPlaylist:(NSString *)playlist
{
    NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableArray *segmentsList = [NSMutableArray array];
    
    for (int i=0 ; i < lines.count; i++) {
        
        SegmentInfo *info = nil;

        NSString *text = lines[i];
        if ([text hasPrefix:@"#EXTINF:"]) {
            info = [SegmentInfo new];
            NSString *duration = [text stringByReplacingOccurrencesOfString:@"#EXTINF:" withString:@""];
            duration = [duration stringByReplacingOccurrencesOfString:@"," withString:@""];
            info.duration = duration;
            
            if ((i+1) < lines.count) {
                text =lines[i+1];
                if ([text hasPrefix:@"http"]) {
                    NSURL *url = [NSURL URLWithString:text];
                    NSString *lastPathComponent = url.lastPathComponent;
                    lastPathComponent = [lastPathComponent stringByReplacingOccurrencesOfString:@".ts" withString:@""];
                    NSArray *nameList = [lastPathComponent componentsSeparatedByString:@"_"];
                    lastPathComponent = [nameList lastObject];
                    info.name = lastPathComponent;
                }
            }
            [segmentsList addObject:info];
        }
    }
    
    [self.segmentsListDict setObject:segmentsList forKey:playlist];
}


- (void)createHtmlFileForSegments
{
    
    NSMutableString *tags = [[NSMutableString alloc] initWithString:@"<!DOCTYPE html><html><body><table>"];
    
    NSMutableArray *allPlaylists = [self.primaryPlaylist mutableCopy];
    [allPlaylists addObjectsFromArray:self.secondaryPlaylist];
    
    NSString *playlist = allPlaylists.firstObject;
    NSMutableArray *refSegmentsList = [self.segmentsListDict objectForKey:playlist];
    [tags appendString:@"<th> Index </th>"];
    
    for (NSString *pList in self.primaryPlaylist) {
        NSURL *url = [NSURL URLWithString:pList];
        NSString *lastComponent = url.lastPathComponent;
        lastComponent = [lastComponent stringByReplacingOccurrencesOfString:@".m3u8" withString:@""];
        [tags appendString:@"<th>"];
        [tags appendString:lastComponent];
        [tags appendString:@"</th>"];
    }
    
    [tags appendString:@"<th></th>"];
    
    for (NSString *pList in self.secondaryPlaylist) {
        NSURL *url = [NSURL URLWithString:pList];
        NSString *lastComponent = url.lastPathComponent;
        [tags appendString:@"<th>"];
        lastComponent = [lastComponent stringByReplacingOccurrencesOfString:@".m3u8" withString:@""];
        [tags appendString:[NSString stringWithFormat:@"(b)-%@",lastComponent]];
        [tags appendString:@"</th>"];
    }
    
    for (int i = 0; i < refSegmentsList.count; i++) {
        [tags appendString:@"<tr>"];
        SegmentInfo *info = refSegmentsList[i];
        
        NSString *playlist = self.secondaryPlaylist.firstObject;
        
        BOOL isPrimaryStreamEqual = YES;
        BOOL isSecondaryStreamEqual = YES;
        SegmentInfo *backupStreamSegmentInfo;
        
        isPrimaryStreamEqual = [self isSegmentTimeEqualsIn:self.primaryPlaylist segmentInfo:info segmentIndex:i];
        if (playlist) {
            NSMutableArray *refSegmentListOnSecondaryStream = [self.segmentsListDict objectForKey:playlist];
            if (refSegmentListOnSecondaryStream.count > i) {
                backupStreamSegmentInfo = [refSegmentListOnSecondaryStream objectAtIndex:i];
                isSecondaryStreamEqual = [self isSegmentTimeEqualsIn:self.secondaryPlaylist segmentInfo:backupStreamSegmentInfo segmentIndex:i];
            }
        }
        
        BOOL isEqual = (isPrimaryStreamEqual && isSecondaryStreamEqual);
        if (isEqual) {
            if (backupStreamSegmentInfo) {
                if (info.duration.floatValue != backupStreamSegmentInfo.duration.floatValue) {
                    isEqual = NO;
                }
            }
        }
        
        [tags appendString:[NSString stringWithFormat:@"<td bgcolor = %@>%d-%@</td>",isEqual ? @"green" : @"red", i,info.name]];
        
        NSMutableString *tag = [self tagsFromPlaylist:self.primaryPlaylist forSegment:info withIndex:i isEqual:isPrimaryStreamEqual];
        
        [tags appendString:tag];
        
        [tags appendString:@"<td></td>"];
        
        if (!backupStreamSegmentInfo) {
            backupStreamSegmentInfo = info;
        }
        tag = [self tagsFromPlaylist:self.secondaryPlaylist forSegment:info withIndex:i isEqual:isSecondaryStreamEqual];
        [tags appendString:tag];
        
        [tags appendString:@"</tr>"];
    }
    [tags appendString:@"</table></body></html>"];
    
    
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
    NSString *path = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"markers"];
    NSError *error;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])    //Does directory already exist?
    {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:path
                                       withIntermediateDirectories:NO
                                                        attributes:nil
                                                             error:&error])
        {
            NSLog(@"Create directory error: %@", error);
        }
    }
    NSTimeInterval interval = [[NSDate date] timeIntervalSince1970];
    path = [path stringByAppendingString:[NSString stringWithFormat:@"/segments_%f.html",interval]];
    NSError *err ;
    [tags writeToFile:path atomically:yearMask encoding:NSUTF8StringEncoding error:&err];
}

- (BOOL)isSegmentTimeEqualsIn:(NSArray *)playlists segmentInfo:(SegmentInfo *)info segmentIndex:(NSInteger)index
{
    BOOL isEqual = YES;
    
    for (NSArray *iPlaylist in playlists) {
        NSMutableArray *segmentsList = [self.segmentsListDict objectForKey:iPlaylist];
        if (segmentsList.count > index) {
            SegmentInfo *segmentInfo = segmentsList[index];
            if (isEqual) {
                if ((segmentInfo.duration.floatValue != info.duration.floatValue) || ![info.name isEqualToString:segmentInfo.name]) {
                    isEqual = NO;
                }
            }
        } else {
            isEqual = NO;
        }
    }
    
    return isEqual;
}

- (NSMutableString *)tagsFromPlaylist:(NSMutableArray *)playlists forSegment:(SegmentInfo *)info withIndex:(NSInteger )index isEqual:(BOOL)equal
{
    NSMutableString *tags = [NSMutableString new];
    for (NSArray *iPlaylist in playlists) {
        [tags appendString:[NSString stringWithFormat:@"<td bgcolor = %@>",equal ? @"green" : @"red"]];
        NSMutableArray *segmentsList = [self.segmentsListDict objectForKey:iPlaylist];
        if (segmentsList.count > index) {
            SegmentInfo *segmentDuration = segmentsList[index];
            [tags appendString:segmentDuration.duration];
        }
        [tags appendString:@"</td>"];
    }
    return tags;
}

@end
