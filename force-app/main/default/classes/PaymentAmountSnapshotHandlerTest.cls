/**
 * @description Unit tests for PaymentAmountSnapshotHandler.
 * Validates negative amounts, missing payment amounts,
 * payment status transitions, and historical paid records.
 */
@IsTest
private class PaymentAmountSnapshotHandlerTest {

    private static final String STATUS_PAID = 'Paid';
    private static final String STATUS_PENDING = 'Pending';

    private static final String NEGATIVE_AMOUNT_ERROR =
        'The amount received cannot be negative.';

    private static final String MISSING_AMOUNT_ERROR =
        'Enter the actual amount received before marking this installment paid.';

    /**
     * @description Creates an in-memory payment term.
     * @param amount Recorded payment amount.
     * @param status Transaction status.
     * @param received Indicates whether payment was received.
     * @return Payment term for validation.
     */
    private static Payment_Term__c createTerm(
        Decimal amount,
        String status,
        Boolean received
    ) {
        return new Payment_Term__c(
            Paid_Amount__c = amount,
            Transaction_Status__c = status,
            Payment_Received__c = received
        );
    }

    /**
     * @description Verifies the expected validation error.
     * @param term Payment term containing validation errors.
     * @param expectedMessage Expected error message.
     */
    private static void assertValidationError(
        Payment_Term__c term,
        String expectedMessage
    ) {
        System.assert(
            term.hasErrors(),
            'Expected a validation error.'
        );

        Boolean found = false;

        for (Database.Error error : term.getErrors()) {
            if (error.getMessage() == expectedMessage) {
                found = true;
                break;
            }
        }

        System.assert(
            found,
            'Expected validation error: ' + expectedMessage
        );
    }

    /**
     * @description Verifies negative amounts are rejected.
     */
    @IsTest
    static void testNegativePaidAmount() {
        Payment_Term__c term = createTerm(
            -100.00,
            STATUS_PENDING,
            false
        );

        Test.startTest();
        PaymentAmountSnapshotHandler.validate(
            new List<Payment_Term__c>{ term },
            null
        );
        Test.stopTest();

        assertValidationError(
            term,
            NEGATIVE_AMOUNT_ERROR
        );
    }

    /**
     * @description Verifies zero paid amount is valid
     * for an unpaid installment.
     */
    @IsTest
    static void testZeroPaidAmount() {
        Payment_Term__c term = createTerm(
            0.00,
            STATUS_PENDING,
            false
        );

        Test.startTest();
        PaymentAmountSnapshotHandler.validate(
            new List<Payment_Term__c>{ term },
            null
        );
        Test.stopTest();

        System.assertEquals(
            false,
            term.hasErrors(),
            'Zero paid amount must be accepted.'
        );
    }

    /**
     * @description Ensures newly paid installments
     * cannot have a missing amount.
     */
    @IsTest
    static void testNewPaidStatusWithoutAmount() {
        Payment_Term__c term = createTerm(
            null,
            STATUS_PAID,
            false
        );

        Test.startTest();
        PaymentAmountSnapshotHandler.validate(
            new List<Payment_Term__c>{ term },
            null
        );
        Test.stopTest();

        assertValidationError(
            term,
            MISSING_AMOUNT_ERROR
        );
    }

    /**
     * @description Verifies Payment_Received__c
     * also triggers amount validation.
     */
    @IsTest
    static void testPaymentReceivedWithoutAmount() {
        Payment_Term__c term = createTerm(
            null,
            STATUS_PENDING,
            true
        );

        Test.startTest();
        PaymentAmountSnapshotHandler.validate(
            new List<Payment_Term__c>{ term },
            null
        );
        Test.stopTest();

        assertValidationError(
            term,
            MISSING_AMOUNT_ERROR
        );
    }

    /**
     * @description Verifies a newly paid installment
     * with a valid amount passes validation.
     */
    @IsTest
    static void testNewPaidStatusWithAmount() {
        Payment_Term__c term = createTerm(
            15000.00,
            STATUS_PAID,
            false
        );

        Test.startTest();
        PaymentAmountSnapshotHandler.validate(
            new List<Payment_Term__c>{ term },
            null
        );
        Test.stopTest();

        System.assertEquals(
            false,
            term.hasErrors(),
            'Paid installment with an amount must be valid.'
        );
    }

    /**
     * @description Ensures previously paid installments
     * do not require a new historical amount.
     */
    @IsTest
    static void testExistingPaidTermWithoutAmount() {
        Id termId = createPaymentTermId();

        Payment_Term__c oldTerm = createTerm(
            null,
            STATUS_PAID,
            false
        );

        Payment_Term__c newTerm = createTerm(
            null,
            STATUS_PAID,
            false
        );

        newTerm.Id = termId;

        Map<Id, Payment_Term__c> oldTerms =
            new Map<Id, Payment_Term__c>{
                termId => oldTerm
            };

        Test.startTest();
        PaymentAmountSnapshotHandler.validate(
            new List<Payment_Term__c>{ newTerm },
            oldTerms
        );
        Test.stopTest();

        System.assertEquals(
            false,
            newTerm.hasErrors(),
            'Previously paid installment must remain valid.'
        );
    }

    /**
     * @description Ensures previously received payments
     * do not require a new historical amount.
     */
    @IsTest
    static void testExistingReceivedPaymentWithoutAmount() {
        Id termId = createPaymentTermId();

        Payment_Term__c oldTerm = createTerm(
            null,
            STATUS_PENDING,
            true
        );

        Payment_Term__c newTerm = createTerm(
            null,
            STATUS_PENDING,
            true
        );

        newTerm.Id = termId;

        Map<Id, Payment_Term__c> oldTerms =
            new Map<Id, Payment_Term__c>{
                termId => oldTerm
            };

        Test.startTest();
        PaymentAmountSnapshotHandler.validate(
            new List<Payment_Term__c>{ newTerm },
            oldTerms
        );
        Test.stopTest();

        System.assertEquals(
            false,
            newTerm.hasErrors(),
            'Previously received payment must remain valid.'
        );
    }

    /**
     * @description Verifies transition from Pending
     * to Paid requires an actual amount.
     */
    @IsTest
    static void testPendingToPaidWithoutAmount() {
        Id termId = createPaymentTermId();

        Payment_Term__c oldTerm = createTerm(
            null,
            STATUS_PENDING,
            false
        );

        Payment_Term__c newTerm = createTerm(
            null,
            STATUS_PAID,
            false
        );

        newTerm.Id = termId;

        Map<Id, Payment_Term__c> oldTerms =
            new Map<Id, Payment_Term__c>{
                termId => oldTerm
            };

        Test.startTest();
        PaymentAmountSnapshotHandler.validate(
            new List<Payment_Term__c>{ newTerm },
            oldTerms
        );
        Test.stopTest();

        assertValidationError(
            newTerm,
            MISSING_AMOUNT_ERROR
        );
    }

    /**
     * @description Verifies transition to payment received
     * requires an actual paid amount.
     */
    @IsTest
    static void testPendingToReceivedWithoutAmount() {
        Id termId = createPaymentTermId();

        Payment_Term__c oldTerm = createTerm(
            null,
            STATUS_PENDING,
            false
        );

        Payment_Term__c newTerm = createTerm(
            null,
            STATUS_PENDING,
            true
        );

        newTerm.Id = termId;

        Map<Id, Payment_Term__c> oldTerms =
            new Map<Id, Payment_Term__c>{
                termId => oldTerm
            };

        Test.startTest();
        PaymentAmountSnapshotHandler.validate(
            new List<Payment_Term__c>{ newTerm },
            oldTerms
        );
        Test.stopTest();

        assertValidationError(
            newTerm,
            MISSING_AMOUNT_ERROR
        );
    }

    /**
     * @description Verifies unpaid installments may
     * retain a null paid amount.
     */
    @IsTest
    static void testUnpaidTermWithNullAmount() {
        Payment_Term__c term = createTerm(
            null,
            STATUS_PENDING,
            false
        );

        Test.startTest();
        PaymentAmountSnapshotHandler.validate(
            new List<Payment_Term__c>{ term },
            null
        );
        Test.stopTest();

        System.assertEquals(
            false,
            term.hasErrors(),
            'Unpaid installment may have no paid amount.'
        );
    }

    /**
     * @description Ensures negative amounts are rejected
     * even when the installment was previously paid.
     */
    @IsTest
    static void testExistingPaidTermWithNegativeAmount() {
        Id termId = createPaymentTermId();

        Payment_Term__c oldTerm = createTerm(
            5000.00,
            STATUS_PAID,
            false
        );

        Payment_Term__c newTerm = createTerm(
            -500.00,
            STATUS_PAID,
            false
        );

        newTerm.Id = termId;

        Map<Id, Payment_Term__c> oldTerms =
            new Map<Id, Payment_Term__c>{
                termId => oldTerm
            };

        Test.startTest();
        PaymentAmountSnapshotHandler.validate(
            new List<Payment_Term__c>{ newTerm },
            oldTerms
        );
        Test.stopTest();

        assertValidationError(
            newTerm,
            NEGATIVE_AMOUNT_ERROR
        );
    }

    /**
     * @description Verifies that only invalid payment
     * terms receive validation errors in a bulk operation.
     */
    @IsTest
    static void testBulkPaymentValidation() {
        Payment_Term__c validTerm = createTerm(
            10000.00,
            STATUS_PAID,
            true
        );

        Payment_Term__c negativeTerm = createTerm(
            -1000.00,
            STATUS_PENDING,
            false
        );

        Payment_Term__c missingAmountTerm = createTerm(
            null,
            STATUS_PAID,
            false
        );

        Payment_Term__c unpaidTerm = createTerm(
            null,
            STATUS_PENDING,
            false
        );

        List<Payment_Term__c> terms =
            new List<Payment_Term__c>{
                validTerm,
                negativeTerm,
                missingAmountTerm,
                unpaidTerm
            };

        Test.startTest();
        PaymentAmountSnapshotHandler.validate(
            terms,
            null
        );
        Test.stopTest();

        System.assertEquals(
            false,
            validTerm.hasErrors(),
            'Valid paid term must not have errors.'
        );

        assertValidationError(
            negativeTerm,
            NEGATIVE_AMOUNT_ERROR
        );

        assertValidationError(
            missingAmountTerm,
            MISSING_AMOUNT_ERROR
        );

        System.assertEquals(
            false,
            unpaidTerm.hasErrors(),
            'Valid unpaid term must not have errors.'
        );
    }

    /**
     * @description Verifies an empty input list
     * is handled without errors.
     */
    @IsTest
    static void testEmptyPaymentTerms() {
        List<Payment_Term__c> terms =
            new List<Payment_Term__c>();

        Test.startTest();
        PaymentAmountSnapshotHandler.validate(
            terms,
            null
        );
        Test.stopTest();

        System.assertEquals(
            true,
            terms.isEmpty(),
            'Empty payment term list must remain empty.'
        );
    }

    /**
     * @description Ensures payment status changes
     * with a valid amount pass validation.
     */
    @IsTest
    static void testPendingToPaidWithValidAmount() {
        Id termId = createPaymentTermId();

        Payment_Term__c oldTerm = createTerm(
            null,
            STATUS_PENDING,
            false
        );

        Payment_Term__c newTerm = createTerm(
            25000.00,
            STATUS_PAID,
            true
        );

        newTerm.Id = termId;

        Map<Id, Payment_Term__c> oldTerms =
            new Map<Id, Payment_Term__c>{
                termId => oldTerm
            };

        Test.startTest();
        PaymentAmountSnapshotHandler.validate(
            new List<Payment_Term__c>{ newTerm },
            oldTerms
        );
        Test.stopTest();

        System.assertEquals(
            false,
            newTerm.hasErrors(),
            'Valid payment transition must pass validation.'
        );
    }

	/**
	* @description Generates a valid Payment_Term__c ID for in-memory validation tests without DML.
	* @return Valid Payment_Term__c identifier.
	*/
	private static Id createPaymentTermId() {
		String keyPrefix = Payment_Term__c.SObjectType.getDescribe().getKeyPrefix();
		return (Id) (keyPrefix + '000000000001');
	}

}