//
//  ViewController.h
//  StreamParser
//
//  Created by K, Santhosh on 01/03/17.
//  Copyright © 2017 K, Santhosh. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ViewController : NSViewController
@property (weak) IBOutlet NSTextFieldCell *urlTextField;
- (IBAction)didTapProcessButton:(id)sender;

@property (weak) IBOutlet NSProgressIndicator *progressIndicator;
@property (weak) IBOutlet NSTextField *label;
@property (weak) IBOutlet NSButton *processButton;

@end

