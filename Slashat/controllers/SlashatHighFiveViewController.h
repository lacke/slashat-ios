//
//  SlashatHighFiveViewController.h
//  Slashat
//
//  Created by Johan Larsson on 2013-09-28.
//  Copyright (c) 2013 Johan Larsson. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ZBarSDK.h"


@interface SlashatHighFiveViewController : UIViewController <UICollectionViewDataSource, ZBarReaderDelegate>

- (IBAction)giveHighFiveButtonPressed:(id)sender;

@end
