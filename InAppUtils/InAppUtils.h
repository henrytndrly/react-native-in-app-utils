#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

#import "RCTBridgeModule.h"
#import "RCTEventEmitter.h"

@interface InAppUtils : RCTEventEmitter <RCTBridgeModule, SKProductsRequestDelegate, SKPaymentTransactionObserver>

@end
