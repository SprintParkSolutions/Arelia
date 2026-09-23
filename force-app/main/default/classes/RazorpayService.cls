/**
 * Outbound HTTP callouts to Razorpay. Always goes through the pre-configured
 * Razorpay_API Named Credential -- never hardcode the Razorpay host, key, or
 * secret, and never build the Authorization header manually; the Named
 * Credential's External Credential injects Basic Auth automatically.
 */
public without sharing class RazorpayService {

    public class RazorpayOrderResult {
        public Boolean success;
        public String orderId;
        public String errorMessage;
    }

    public static RazorpayOrderResult createOrder(Decimal amountInRupees, String receipt, String currencyCode) {
        RazorpayOrderResult result = new RazorpayOrderResult();

        Map<String, Object> body = new Map<String, Object>{
            'amount' => PaymentUtil.toPaise(amountInRupees),
            'currency' => String.isBlank(currencyCode) ? 'INR' : currencyCode,
            'receipt' => receipt,
            'payment_capture' => 1
        };

        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Razorpay_API/v1/orders');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(body));
        req.setTimeout(30000);

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                result.success = true;
                result.orderId = (String) responseBody.get('id');
            } else {
                result.success = false;
                result.errorMessage = 'Razorpay order creation failed (HTTP ' + res.getStatusCode() + '): ' + res.getBody();
            }
        } catch (Exception ex) {
            result.success = false;
            result.errorMessage = 'Razorpay order creation error: ' + ex.getMessage();
        }

        return result;
    }
}