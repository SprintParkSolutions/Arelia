/**
 * @description Tests AreliaPaymentNotificationTrigger
 * for before insert, before update, and after update.
 * Covers payment validation and successful DML operations.
 */
@IsTest
private class AreliaPaymentNotificationTriggerTest {

    private static final String STATUS_PENDING = 'Pending';
    private static final String STATUS_PAID = 'Paid';

    private static final String NEGATIVE_AMOUNT_ERROR = 'The amount received cannot be negative.';

    private static final String MISSING_AMOUNT_ERROR = 'Enter the actual amount received before marking this installment paid.';

    private static final Decimal VALID_AMOUNT = 25000.00;
    private static final Decimal NEGATIVE_AMOUNT = -500.00;

    /**
     * @description Creates payment test records using
     * the existing TestDataUtility.
     */
    private static Payment_Term__c createTestPaymentTerm() {
        Contact testContact = TestDataUtility.createContact(
            'Payment Payer',
            'paymentpayer' + DateTime.now().getTime()
                + '@example.com',
            'Test@1234'
        );

        Project__c testProject = TestDataUtility.createProject(
            'Payment Notification Test Project',
            1000000,
            testContact.Id
        );

        return TestDataUtility.createPaymentTerm(
            testProject.Id,
            'Installment 1',
            25
        );
    }

    /**
     * @description Configures an existing payment term
     * as unpaid before testing payment transitions.
     * @param term Payment term to update.
     */
    private static void configureUnpaidTerm(Payment_Term__c term) {
        term.Transaction_Status__c = STATUS_PENDING;
        term.Payment_Received__c = false;
        term.Paid_Amount__c = null;

        update term;
    }

    /**
     * @description Checks whether a DML result contains
     * the expected validation error.
     * @param errors Errors returned from DML.
     * @param expectedMessage Expected validation message.
     */
    private static void assertExpectedError(List<Database.Error> errors, String expectedMessage) {
        Boolean found = false;

        for (Database.Error error : errors) {
            if (
                error.getMessage() != null
                && error.getMessage().contains(expectedMessage)
            ) {
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
     * @description Verifies successful payment term
     * creation executes the before-insert trigger.
     */
    @IsTest
    static void testBeforeInsertValidPaymentTerm() {
        Test.startTest();

        Payment_Term__c term = createTestPaymentTerm();

        Test.stopTest();

        System.assertNotEquals(
            null,
            term.Id,
            'Payment term must be created successfully.'
        );

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Payment_Term__c
                WHERE Id = :term.Id
            ],
            'Inserted payment term must exist.'
        );
    }

    /**
     * @description Verifies negative paid amounts
     * are rejected during before insert.
     */
    @IsTest
    static void testBeforeInsertNegativeAmount() {
        Payment_Term__c existingTerm = createTestPaymentTerm();
        Payment_Term__c newTerm = existingTerm.clone(false, false, false, false);
        newTerm.Transaction_Status__c = STATUS_PENDING;
        newTerm.Payment_Received__c = false;
        newTerm.Paid_Amount__c = NEGATIVE_AMOUNT;
        Test.startTest();

        Database.SaveResult result = Database.insert(newTerm, false);
        Test.stopTest();
        System.assertEquals(
            false,
            result.isSuccess(),
            'Negative payment amount must prevent insertion.'
        );

        assertExpectedError(
            result.getErrors(),
            NEGATIVE_AMOUNT_ERROR
        );
    }

    /**
     * @description Verifies newly inserted paid terms
     * require the actual received amount.
     */
    @IsTest
    static void testBeforeInsertPaidWithoutAmount() {
        Payment_Term__c existingTerm = createTestPaymentTerm();
        Payment_Term__c newTerm = existingTerm.clone(false, false, false, false);
        newTerm.Transaction_Status__c = STATUS_PAID;
        newTerm.Payment_Received__c = true;
        newTerm.Paid_Amount__c = null;
        Test.startTest();
        Database.SaveResult result = Database.insert(
            newTerm,
            false
        );

        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess(),
            'Paid term without amount must be rejected.'
        );

        assertExpectedError(
            result.getErrors(),
            MISSING_AMOUNT_ERROR
        );
    }

    /**
     * @description Verifies negative payment amounts
     * are rejected during before update.
     */
    @IsTest
    static void testBeforeUpdateNegativeAmount() {
        Payment_Term__c term = createTestPaymentTerm();

        term.Paid_Amount__c = NEGATIVE_AMOUNT;

        Test.startTest();

        Database.SaveResult result = Database.update(
            term,
            false
        );

        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess(),
            'Negative amount must prevent payment update.'
        );

        assertExpectedError(
            result.getErrors(),
            NEGATIVE_AMOUNT_ERROR
        );
    }

    /**
     * @description Verifies changing Pending to Paid
     * without an amount is rejected.
     */
    @IsTest
    static void testBeforeUpdatePaidWithoutAmount() {
        Payment_Term__c term = createTestPaymentTerm();

        configureUnpaidTerm(term);

        term.Transaction_Status__c = STATUS_PAID;
        term.Payment_Received__c = true;
        term.Paid_Amount__c = null;

        Test.startTest();

        Database.SaveResult result = Database.update(
            term,
            false
        );

        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess(),
            'Newly paid term must require actual amount.'
        );

        assertExpectedError(
            result.getErrors(),
            MISSING_AMOUNT_ERROR
        );
    }

    /**
     * @description Verifies payment received flag
     * cannot be enabled without an actual amount.
     */
    @IsTest
    static void testBeforeUpdateReceivedWithoutAmount() {
        Payment_Term__c term = createTestPaymentTerm();

        configureUnpaidTerm(term);

        term.Transaction_Status__c = STATUS_PENDING;
        term.Payment_Received__c = true;
        term.Paid_Amount__c = null;

        Test.startTest();

        Database.SaveResult result = Database.update(
            term,
            false
        );

        Test.stopTest();

        System.assertEquals(
            false,
            result.isSuccess(),
            'Payment received without amount must fail.'
        );

        assertExpectedError(
            result.getErrors(),
            MISSING_AMOUNT_ERROR
        );
    }

    /**
     * @description Verifies an unpaid installment
     * can be updated without a received amount.
     */
    @IsTest
    static void testBeforeUpdateValidUnpaidTerm() {
        Payment_Term__c term = createTestPaymentTerm();

        configureUnpaidTerm(term);

        term.Payment_Received__c = false;
        term.Paid_Amount__c = null;

        Test.startTest();

        Database.SaveResult result = Database.update(
            term,
            false
        );

        Test.stopTest();

        System.assertEquals(
            true,
            result.isSuccess(),
            'Valid unpaid term must update successfully.'
        );
    }

    /**
     * @description Verifies successful payment update
     * executes the after-update trigger path.
     */
    @IsTest
    static void testAfterUpdatePaymentPaidSuccessfully() {
        Payment_Term__c term = createTestPaymentTerm();

        configureUnpaidTerm(term);

        term.Transaction_Status__c = STATUS_PAID;
        term.Payment_Received__c = true;
        term.Paid_Amount__c = VALID_AMOUNT;

        Test.startTest();

        Database.SaveResult result = Database.update(
            term,
            false
        );

        Test.stopTest();

        System.assertEquals(
            true,
            result.isSuccess(),
            'Valid payment must update successfully.'
        );

        Payment_Term__c updatedTerm = [
            SELECT
                Id,
                Transaction_Status__c,
                Payment_Received__c,
                Paid_Amount__c
            FROM Payment_Term__c
            WHERE Id = :term.Id
            LIMIT 1
        ];

        System.assertEquals(
            STATUS_PAID,
            updatedTerm.Transaction_Status__c,
            'Transaction status must be Paid.'
        );

        System.assertEquals(
            true,
            updatedTerm.Payment_Received__c,
            'Payment received flag must be true.'
        );

        System.assertEquals(
            VALID_AMOUNT,
            updatedTerm.Paid_Amount__c,
            'Actual received amount must be saved.'
        );
    }

    /**
     * @description Verifies a paid installment with
     * a valid amount can be updated again.
     */
    @IsTest
    static void testAfterUpdateExistingPaidTerm() {
        Payment_Term__c term = createTestPaymentTerm();

        configureUnpaidTerm(term);

        term.Transaction_Status__c = STATUS_PAID;
        term.Payment_Received__c = true;
        term.Paid_Amount__c = VALID_AMOUNT;

        update term;

        Payment_Term__c updatedTerm = [
            SELECT
                Id,
                Transaction_Status__c,
                Payment_Received__c,
                Paid_Amount__c
            FROM Payment_Term__c
            WHERE Id = :term.Id
            LIMIT 1
        ];

        updatedTerm.Paid_Amount__c = 30000.00;

        Test.startTest();

        Database.SaveResult result = Database.update(
            updatedTerm,
            false
        );

        Test.stopTest();

        System.assertEquals(
            true,
            result.isSuccess(),
            'Existing paid term must allow valid updates.'
        );

        Payment_Term__c finalTerm = [
            SELECT Paid_Amount__c
            FROM Payment_Term__c
            WHERE Id = :term.Id
            LIMIT 1
        ];

        System.assertEquals(
            30000.00,
            finalTerm.Paid_Amount__c,
            'Updated paid amount must be saved.'
        );
    }

    /**
     * @description Verifies a valid zero amount
     * does not trigger negative amount validation.
     */
    @IsTest
    static void testBeforeUpdateZeroAmount() {
        Payment_Term__c term = createTestPaymentTerm();

        configureUnpaidTerm(term);

        term.Paid_Amount__c = 0.00;

        Test.startTest();

        Database.SaveResult result = Database.update(
            term,
            false
        );

        Test.stopTest();

        System.assertEquals(
            true,
            result.isSuccess(),
            'Zero must be accepted as non-negative.'
        );
    }
}