/**
 * @description Unit tests for PaymentException.
 */
@isTest
private class PaymentExceptionTest {

    @isTest
    static void testExceptionMessageIsPreserved() {
        String message = 'Payment term not found.';
        Boolean caught = false;

        try {
            throw new PaymentException(message);
        } catch (PaymentException pe) {
            caught = true;
            System.assertEquals(message, pe.getMessage(), 'Exception message should match what was thrown.');
        }

        System.assert(caught, 'PaymentException should have been thrown and caught.');
    }
}