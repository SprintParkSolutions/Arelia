/**
 * @description Unit tests for RazorpayService outbound callouts.
 *              Verifies successful order creation and error handling.
 */
@IsTest
private class RazorpayServiceTest {

    private class RazorpaySuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"order_test_123"}');
            res.setStatusCode(201);
            return res;
        }
    }

    private class RazorpayFailureMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":"Invalid request"}');
            res.setStatusCode(400);
            return res;
        }
    }

    @IsTest
    static void testCreateOrderReturnsSuccessResult() {
        Test.setMock(HttpCalloutMock.class, new RazorpaySuccessMock());

        RazorpayService.RazorpayOrderResult result = RazorpayService.createOrder(25000, 'receipt_123', 'INR');

        System.assertEquals(true, result.success, 'Order creation should succeed when Razorpay returns 2xx.');
        System.assertEquals('order_test_123', result.orderId, 'Order result should return the Razorpay order ID.');
        System.assertEquals(null, result.errorMessage, 'Error message should be null on successful order creation.');
    }

    @IsTest
    static void testCreateOrderReturnsFailureResultOnHttpError() {
        Test.setMock(HttpCalloutMock.class, new RazorpayFailureMock());

        RazorpayService.RazorpayOrderResult result = RazorpayService.createOrder(25000, 'receipt_123', 'INR');

        System.assertEquals(false, result.success, 'Order creation should fail for non-2xx responses.');
        System.assertEquals(null, result.orderId, 'Order ID should be null when the callout fails.');
        System.assert(result.errorMessage.contains('HTTP 400'), 'Error message should mention the HTTP status code.');
    }
}