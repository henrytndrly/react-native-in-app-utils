#import "InAppUtils.h"
#import <StoreKit/StoreKit.h>
#import "RCTLog.h"
#import "RCTUtils.h"
#import "SKProduct+StringPrice.h"

@implementation InAppUtils
{
    NSArray *products;
    NSMutableDictionary *_callbacks;
    bool hasListeners;
}

- (instancetype)init
{

    if ((self = [super init])) {
        _callbacks = [[NSMutableDictionary alloc] init];
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
        hasListeners = false;
    }
    return self;
}

// Will be called when this module's first listener is added.
-(void)startObserving {
    hasListeners = YES;
    // Set up any upstream listeners or background tasks as necessary
    // NSLog(@"started observing");
}

// Will be called when this module's last listener is removed, or on dealloc.
-(void)stopObserving {
    hasListeners = NO;
    // Remove upstream listeners, stop unnecessary background tasks
    // NSLog(@"stopped observing");
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

RCT_EXPORT_MODULE()


- (NSArray<NSString *> *)supportedEvents
{
    return @[@"pendingTransaction"];
}

- (void)paymentQueue:(SKPaymentQueue *)queue
 updatedTransactions:(NSArray *)transactions
{
    for (SKPaymentTransaction *transaction in transactions) {
        switch (transaction.transactionState) {
            case SKPaymentTransactionStateFailed: {
                NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
                RCTResponseSenderBlock callback = _callbacks[key];
                if (callback) {
                    callback(@[RCTJSErrorFromNSError(transaction.error)]);
                    [_callbacks removeObjectForKey:key];
                } else {
                    RCTLogWarn(@"InAppUtils No callback registered for transaction with state failed.");
                }
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            }
            case SKPaymentTransactionStatePurchased: {
                NSString *key = RCTKeyForInstance(transaction.payment.productIdentifier);
                RCTResponseSenderBlock callback = _callbacks[key];
                if (callback) {
                    NSDictionary *purchase = @{
                                              @"transactionIdentifier": transaction.transactionIdentifier,
                                              @"productIdentifier": transaction.payment.productIdentifier,
                                              };
                    callback(@[[NSNull null], purchase]);
                    [_callbacks removeObjectForKey:key];
                } else {
                    RCTLogWarn(@"InAppUtils: No callback registered for transaction with state purchased.");
                }
                // Don't want to finish the transaction here -> we've not saved it
                // to the database yet, so may have issues doing that which may cause
                // this purchase to be lost if not done.
                // [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            }
            case SKPaymentTransactionStateRestored:
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                break;
            case SKPaymentTransactionStatePurchasing:
                break;
            case SKPaymentTransactionStateDeferred:
                break;
            default:
                break;
        }
    }
}

RCT_EXPORT_METHOD(processDefaultQueue) {

    if (!hasListeners) {
        // do something here...
        return;
    }

    NSString *transState;

    NSURL *receiptUrl;
    NSData *receiptData;


    if (SKPaymentQueue.defaultQueue.transactions.count > 0) {
        receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
        receiptData = [NSData dataWithContentsOfURL:receiptUrl];

        for(SKPaymentTransaction *transaction in SKPaymentQueue.defaultQueue.transactions)
        {

            switch (transaction.transactionState) {
                case SKPaymentTransactionStateFailed:
                    transState = @"failed";
                    break;
                case SKPaymentTransactionStatePurchased:
                    transState = @"purchased";
                    break;
                case SKPaymentTransactionStateRestored:
                    transState = @"restored";
                    break;
                case SKPaymentTransactionStatePurchasing:
                    transState = @"purchasing";
                    break;
                case SKPaymentTransactionStateDeferred:
                    transState = @"deferred";
                    break;
                default:
                    transState = @"other";
                    break;
            }

            [self sendEventWithName:@"pendingTransaction"
                               body:@{
                                      @"transactionIdentifier": transaction.transactionIdentifier,
                                      @"transactionState": transState,
                                      @"receiptData": [receiptData base64EncodedStringWithOptions:0]
                                      }];
        }
    }
    // no pending transactions, so don't need to do anything...
    // else {
    //     [self sendEventWithName:@"pendingTransaction"
    //                        body:@{@"transCount": @0}];
    // }
}

RCT_EXPORT_METHOD(purchaseProduct:(NSString *)productIdentifier
                  callback:(RCTResponseSenderBlock)callback)
{
    SKProduct *product;
    for(SKProduct *p in products)
    {
        if([productIdentifier isEqualToString:p.productIdentifier]) {
            product = p;
            break;
        }
    }

    if(product) {
        SKPayment *payment = [SKPayment paymentWithProduct:product];
        [[SKPaymentQueue defaultQueue] addPayment:payment];
        _callbacks[RCTKeyForInstance(payment.productIdentifier)] = callback;
    } else {
        callback(@[@"invalid_product"]);
    }
}

- (void)paymentQueue:(SKPaymentQueue *)queue
restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    NSString *key = RCTKeyForInstance(@"restoreRequest");
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        callback(@[@"restore_failed"]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for restore product request.");
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    NSString *key = RCTKeyForInstance(@"restoreRequest");
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        NSMutableArray *productsArrayForJS = [NSMutableArray array];
        for(SKPaymentTransaction *transaction in queue.transactions){
            if(transaction.transactionState == SKPaymentTransactionStateRestored) {
                NSDictionary *purchase = @{
                    @"originalTransactionIdentifier": transaction.originalTransaction.transactionIdentifier,
                    @"transactionIdentifier": transaction.transactionIdentifier,
                    @"productIdentifier": transaction.payment.productIdentifier
                };

                [productsArrayForJS addObject:purchase];
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
            }
        }
        callback(@[[NSNull null], productsArrayForJS]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for restore product request.");
    }
}

RCT_EXPORT_METHOD(finishTransaction:(NSString *)transactionIdentifier)
{
    // find the specific transaction, and finish it.
    for(SKPaymentTransaction *transaction in SKPaymentQueue.defaultQueue.transactions){
        if ([transactionIdentifier isEqualToString:transaction.transactionIdentifier]) {
            [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
        }
    }
}

RCT_EXPORT_METHOD(restorePurchases:(RCTResponseSenderBlock)callback)
{
    NSString *restoreRequest = @"restoreRequest";
    _callbacks[RCTKeyForInstance(restoreRequest)] = callback;
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
}

RCT_EXPORT_METHOD(loadProducts:(NSArray *)productIdentifiers
                  callback:(RCTResponseSenderBlock)callback)
{
    if([SKPaymentQueue canMakePayments]){
        SKProductsRequest *productsRequest = [[SKProductsRequest alloc]
                                              initWithProductIdentifiers:[NSSet setWithArray:productIdentifiers]];
        productsRequest.delegate = self;
        _callbacks[RCTKeyForInstance(productsRequest)] = callback;
        [productsRequest start];
    } else {
        callback(@[@"not_available"]);
    }
}

RCT_EXPORT_METHOD(receiptData:(RCTResponseSenderBlock)callback)
{
    NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptUrl];
    if (!receiptData) {
      callback(@[@"not_available"]);
    } else {
      callback(@[[NSNull null], [receiptData base64EncodedStringWithOptions:0]]);
    }
}

// SKProductsRequestDelegate protocol method
- (void)productsRequest:(SKProductsRequest *)request
     didReceiveResponse:(SKProductsResponse *)response
{
    NSString *key = RCTKeyForInstance(request);
    RCTResponseSenderBlock callback = _callbacks[key];
    if (callback) {
        products = [NSMutableArray arrayWithArray:response.products];
        NSMutableArray *productsArrayForJS = [NSMutableArray array];
        for(SKProduct *item in response.products) {
            NSDictionary *product = @{
                                      @"identifier": item.productIdentifier,
                                      @"price": item.price,
                                      @"currencySymbol": [item.priceLocale objectForKey:NSLocaleCurrencySymbol],
                                      @"currencyCode": [item.priceLocale objectForKey:NSLocaleCurrencyCode],
                                      @"priceString": item.priceString,
                                      @"downloadable": item.downloadable ? @"true" : @"false" ,
                                      @"description": item.localizedDescription ? item.localizedDescription : @"",
                                      @"title": item.localizedTitle ? item.localizedTitle : @"",
                                      };
            [productsArrayForJS addObject:product];
        }
        callback(@[[NSNull null], productsArrayForJS]);
        [_callbacks removeObjectForKey:key];
    } else {
        RCTLogWarn(@"No callback registered for load product request.");
    }
}

- (void)dealloc
{
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

#pragma mark Private

static NSString *RCTKeyForInstance(id instance)
{
    return [NSString stringWithFormat:@"%p", instance];
}

@end
