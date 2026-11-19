/**
 * -----------------------------------------------------------------------------
 * Class Name      : ProformaClientResponseQueueableTest
 * Author          : Arelia
 * Created Date    : Oct 7, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 7, 2026
 * Description     : Test class for ProformaClientResponseQueueable.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ProformaClientResponseQueueableTest {

    private static final String STATUS_SENT = 'Sent';
    private static final String STATUS_APPROVED = 'Approved';

    private static final String INITIAL_COMMENT =
        'Initial client comment';

    private static final String UPDATED_COMMENT =
        'Client approved the proforma invoice';

    private static final String INITIAL_TOKEN =
        'initial-secure-token';

    private static final String UPDATED_TOKEN =
        'updated-secure-token';


    /**
     * Creates a Proforma Invoice used by the test methods.
     *
     * @return Inserted Proforma Invoice.
     */
    private static Proforma_Invoice__c createInvoice() {

        Proforma_Invoice__c invoice =
            new Proforma_Invoice__c(
                Status__c = STATUS_SENT,
                Client_Comments__c = INITIAL_COMMENT,
                Secure_Token__c = INITIAL_TOKEN
            );

        insert invoice;

        return invoice;
    }


    /**
     * Retrieves the Proforma Invoice after queueable processing.
     *
     * @param invoiceId Proforma Invoice Id.
     * @return Refreshed Proforma Invoice.
     */
    private static Proforma_Invoice__c getInvoice(
        Id invoiceId
    ) {

        return [
            SELECT
                Id,
                Status__c,
                Client_Comments__c,
                Secure_Token__c
            FROM Proforma_Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
        ];
    }


    /**
     * Verifies that status, comments and secure token
     * are updated successfully.
     */
    @IsTest
    static void updatesInvoiceSuccessfully() {

        Proforma_Invoice__c invoice =
            createInvoice();

        String comments =
            '  ' + UPDATED_COMMENT + '  ';

        String token =
            '  ' + UPDATED_TOKEN + '  ';

        Test.startTest();

        System.enqueueJob(
            new ProformaClientResponseQueueable(
                invoice.Id,
                STATUS_APPROVED,
                comments,
                token
            )
        );

        Test.stopTest();

        Proforma_Invoice__c updatedInvoice =
            getInvoice(invoice.Id);

        Assert.areEqual(
            STATUS_APPROVED,
            updatedInvoice.Status__c,
            'Invoice status should be updated.'
        );

        Assert.areEqual(
            UPDATED_COMMENT,
            updatedInvoice.Client_Comments__c,
            'Client comments should be trimmed and updated.'
        );

        Assert.areEqual(
            UPDATED_TOKEN,
            updatedInvoice.Secure_Token__c,
            'Secure token should be trimmed and updated.'
        );
    }


    /**
     * Verifies that existing comments and token are preserved
     * when blank values are provided.
     */
    @IsTest
    static void preservesValuesWhenOptionalInputsBlank() {

        Proforma_Invoice__c invoice =
            createInvoice();

        Test.startTest();

        new ProformaClientResponseQueueable(
            invoice.Id,
            STATUS_APPROVED,
            '   ',
            '   '
        ).execute(null);

        Test.stopTest();

        Proforma_Invoice__c updatedInvoice =
            getInvoice(invoice.Id);

        Assert.areEqual(
            STATUS_APPROVED,
            updatedInvoice.Status__c,
            'Status should still be updated.'
        );

        Assert.areEqual(
            INITIAL_COMMENT,
            updatedInvoice.Client_Comments__c,
            'Existing comments should remain unchanged.'
        );

        Assert.areEqual(
            INITIAL_TOKEN,
            updatedInvoice.Secure_Token__c,
            'Existing secure token should remain unchanged.'
        );
    }


    /**
     * Verifies processing stops when invoice Id is null.
     */
    @IsTest
    static void nullInvoiceIdReturnsWithoutUpdate() {

        Proforma_Invoice__c invoice =
            createInvoice();

        Test.startTest();

        new ProformaClientResponseQueueable(
            null,
            STATUS_APPROVED,
            UPDATED_COMMENT,
            UPDATED_TOKEN
        ).execute(null);

        Test.stopTest();

        Proforma_Invoice__c unchangedInvoice =
            getInvoice(invoice.Id);

        Assert.areEqual(
            STATUS_SENT,
            unchangedInvoice.Status__c,
            'Status should remain unchanged when invoice Id is null.'
        );

        Assert.areEqual(
            INITIAL_COMMENT,
            unchangedInvoice.Client_Comments__c,
            'Comments should remain unchanged.'
        );

        Assert.areEqual(
            INITIAL_TOKEN,
            unchangedInvoice.Secure_Token__c,
            'Secure token should remain unchanged.'
        );
    }


    /**
     * Verifies processing stops when status is null.
     */
    @IsTest
    static void nullStatusReturnsWithoutUpdate() {

        Proforma_Invoice__c invoice =
            createInvoice();

        Test.startTest();

        new ProformaClientResponseQueueable(
            invoice.Id,
            null,
            UPDATED_COMMENT,
            UPDATED_TOKEN
        ).execute(null);

        Test.stopTest();

        Proforma_Invoice__c unchangedInvoice =
            getInvoice(invoice.Id);

        Assert.areEqual(
            STATUS_SENT,
            unchangedInvoice.Status__c,
            'Status should remain unchanged when status is null.'
        );

        Assert.areEqual(
            INITIAL_COMMENT,
            unchangedInvoice.Client_Comments__c,
            'Comments should remain unchanged.'
        );

        Assert.areEqual(
            INITIAL_TOKEN,
            unchangedInvoice.Secure_Token__c,
            'Secure token should remain unchanged.'
        );
    }


    /**
     * Verifies processing stops when status contains
     * only whitespace.
     */
    @IsTest
    static void blankStatusReturnsWithoutUpdate() {

        Proforma_Invoice__c invoice =
            createInvoice();

        Test.startTest();

        new ProformaClientResponseQueueable(
            invoice.Id,
            '   ',
            UPDATED_COMMENT,
            UPDATED_TOKEN
        ).execute(null);

        Test.stopTest();

        Proforma_Invoice__c unchangedInvoice =
            getInvoice(invoice.Id);

        Assert.areEqual(
            STATUS_SENT,
            unchangedInvoice.Status__c,
            'Status should remain unchanged when status is blank.'
        );
    }


    /**
     * Verifies the queueable returns safely when the supplied
     * invoice Id no longer exists.
     */
    @IsTest
    static void missingInvoiceReturnsWithoutError() {

        Proforma_Invoice__c invoice =
            createInvoice();

        Id deletedInvoiceId =
            invoice.Id;

        delete invoice;

        Test.startTest();

        new ProformaClientResponseQueueable(
            deletedInvoiceId,
            STATUS_APPROVED,
            UPDATED_COMMENT,
            UPDATED_TOKEN
        ).execute(null);

        Test.stopTest();

        Integer invoiceCount = [
            SELECT COUNT()
            FROM Proforma_Invoice__c
            WHERE Id = :deletedInvoiceId
        ];

        Assert.areEqual(
            0,
            invoiceCount,
            'Deleted invoice should not be restored or updated.'
        );
    }


    /**
     * Verifies null optional values do not overwrite
     * existing invoice values.
     */
    @IsTest
    static void preservesValuesWhenOptionalInputsNull() {

        Proforma_Invoice__c invoice =
            createInvoice();

        Test.startTest();

        new ProformaClientResponseQueueable(
            invoice.Id,
            STATUS_APPROVED,
            null,
            null
        ).execute(null);

        Test.stopTest();

        Proforma_Invoice__c updatedInvoice =
            getInvoice(invoice.Id);

        Assert.areEqual(
            STATUS_APPROVED,
            updatedInvoice.Status__c,
            'Status should be updated.'
        );

        Assert.areEqual(
            INITIAL_COMMENT,
            updatedInvoice.Client_Comments__c,
            'Null comments must not overwrite existing comments.'
        );

        Assert.areEqual(
            INITIAL_TOKEN,
            updatedInvoice.Secure_Token__c,
            'Null token must not overwrite the existing token.'
        );
    }
}