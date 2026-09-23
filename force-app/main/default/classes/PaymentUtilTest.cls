/**
 * @description Unit tests for PaymentUtil: paise/rupee conversion, Razorpay
 * signature verification, and Indian-format amount rendering.
 */
@isTest
private class PaymentUtilTest {

    @isTest
    static void testToPaiseConvertsRupeesToPaise() {
        System.assertEquals(0L, PaymentUtil.toPaise(null));
        System.assertEquals(123456L, PaymentUtil.toPaise(1234.56));
        System.assertEquals(10000L, PaymentUtil.toPaise(99.999));
    }

    @isTest
    static void testToRupeesConvertsPaiseToRupees() {
        System.assertEquals(0, PaymentUtil.toRupees(null));
        System.assertEquals(1234.56, PaymentUtil.toRupees(123456));
    }

    @isTest
    static void testVerifyPaymentSignatureBlankInputsReturnFalse() {
        System.assertEquals(false, PaymentUtil.verifyPaymentSignature(null, 'pay_1', 'sig_1'));
        System.assertEquals(false, PaymentUtil.verifyPaymentSignature('order_1', null, 'sig_1'));
        System.assertEquals(false, PaymentUtil.verifyPaymentSignature('order_1', 'pay_1', null));
    }

    @isTest
    static void testVerifyPaymentSignatureMatchesExpectedMac() {
        Razorpay_Config__mdt config = [SELECT Key_Secret__c FROM Razorpay_Config__mdt WHERE DeveloperName = 'Default' LIMIT 1];
        String payload = 'order_1|pay_1';
        Blob mac = Crypto.generateMac('hmacSHA256', Blob.valueOf(payload), Blob.valueOf(config.Key_Secret__c));
        String expectedSignature = EncodingUtil.convertToHex(mac);

        System.assertEquals(true, PaymentUtil.verifyPaymentSignature('order_1', 'pay_1', expectedSignature));
        System.assertEquals(true, PaymentUtil.verifyPaymentSignature('order_1', 'pay_1', expectedSignature.toUpperCase()));
        System.assertEquals(false, PaymentUtil.verifyPaymentSignature('order_1', 'pay_1', 'not_the_right_signature'));
    }

    @isTest
    static void testVerifyWebhookSignatureBlankInputsReturnFalse() {
        System.assertEquals(false, PaymentUtil.verifyWebhookSignature(null, 'sig_1'));
        System.assertEquals(false, PaymentUtil.verifyWebhookSignature('{}', null));
    }

    @isTest
    static void testVerifyWebhookSignatureMatchesExpectedMac() {
        Razorpay_Config__mdt config = [SELECT Webhook_Secret__c FROM Razorpay_Config__mdt WHERE DeveloperName = 'Default' LIMIT 1];
        String rawBody = '{"event":"payment.captured"}';
        Blob mac = Crypto.generateMac('hmacSHA256', Blob.valueOf(rawBody), Blob.valueOf(config.Webhook_Secret__c));
        String expectedSignature = EncodingUtil.convertToHex(mac);

        System.assertEquals(true, PaymentUtil.verifyWebhookSignature(rawBody, expectedSignature));
        System.assertEquals(false, PaymentUtil.verifyWebhookSignature(rawBody, 'not_the_right_signature'));
    }

    @isTest
    static void testGetPublicKeyIdReturnsConfiguredKeyId() {
        Razorpay_Config__mdt config = [SELECT Key_Id__c FROM Razorpay_Config__mdt WHERE DeveloperName = 'Default' LIMIT 1];
        System.assertEquals(config.Key_Id__c, PaymentUtil.getPublicKeyId());
    }

    @isTest
    static void testAmountToWordsNullReturnsEmptyString() {
        System.assertEquals('', PaymentUtil.amountToWords(null));
    }

    @isTest
    static void testAmountToWordsZeroReturnsZero() {
        System.assertEquals('Rupees Zero Only', PaymentUtil.amountToWords(0));
    }

    @isTest
    static void testAmountToWordsCoversAllPlaceValuesAndPaise() {
        System.assertEquals(
            'Rupees One Crore Twenty-Three Lakh Forty-Five Thousand Six Hundred Seventy-Eight and Seventy-Five Paise Only',
            PaymentUtil.amountToWords(12345678.75)
        );
    }

    @isTest
    static void testAmountToWordsRoundTensHasNoHyphen() {
        System.assertEquals('Rupees Twenty Thousand Only', PaymentUtil.amountToWords(20000));
    }

    @isTest
    static void testFormatIndianCurrencyNullReturnsEmptyString() {
        System.assertEquals('', PaymentUtil.formatIndianCurrency(null));
    }

    @isTest
    static void testFormatIndianCurrencySmallAmountNoGrouping() {
        System.assertEquals('₹100.05', PaymentUtil.formatIndianCurrency(100.05));
    }

    @isTest
    static void testFormatIndianCurrencyLargeAmountUsesIndianGrouping() {
        System.assertEquals('₹12,34,56,789.50', PaymentUtil.formatIndianCurrency(123456789.5));
    }
}