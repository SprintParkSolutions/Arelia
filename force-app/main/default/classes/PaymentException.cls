/**
 * Thrown for all expected payment-flow failures (not-found, not-authorized,
 * not-payable, signature mismatch) so callers can distinguish business-rule
 * rejections from unexpected system errors.
 */
public class PaymentException extends Exception {
}