//
//  SCTE-Marker.h
//  StreamParser
//
//  Created by K, Santhosh on 01/03/17.
//  Copyright © 2017 K, Santhosh. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SCTEMarker : NSObject

@property (nonatomic, strong) NSString *markerName;
@property (nonatomic, strong) NSNumber *time;

@end
