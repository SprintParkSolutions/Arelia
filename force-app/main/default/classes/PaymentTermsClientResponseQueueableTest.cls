/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : PaymentTermsClientResponseQueueableTest
 * Author          : Arelia
 * Created Date    : Oct 7, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 7, 2026
 * Description     : Test class for PaymentTermsClientResponseQueueable.
 */

@IsTest
private class PaymentTermsClientResponseQueueableTest {

    private static final String STATUS_CLIENT_APPROVED =
        'Client Approved';

    private static final String STATUS_CLIENT_CHANGES =
        'Client Requested Changes';

    private static final String INITIAL_REMARKS =
        'Initial client remarks';

    private static final String UPDATED_REMARKS =
        'Please revise the payment schedule.';

    /**
     * Creates the Account required by the test Opportunity.
     *
     * @return Inserted Account.
     */
    private static Account createAccount() {
        Account accountRecord = new Account(
            Name = 'Payment Terms Test Account'
        );

        insert accountRecord;

        return accountRecord;
    }

    /**
     * Creates an Opportunity for Queueable testing.
     *
     * @param accountId Account related to the Opportunity.
     * @param status Payment Terms status.
     * @param remarks Existing client remarks.
     * @return Inserted Opportunity.
     */
    private static Opportunity createOpportunity(
        Id accountId,
        String status,
        String remarks
    ) {
        Opportunity opportunity = new Opportunity(
            Name = 'Payment Terms Test Opportunity',
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Payment_Terms_Status__c = status,
            Payment_Term_Client_Remarks__c = remarks
        );

        setAreliaRecordType(opportunity);

        insert opportunity;

        return opportunity;
    }

   /**
	* Assigns the Arelia Opportunity record type when it exists.
	*
	* @param opportunity Opportunity being prepared for insertion.
	*/
	private static void setAreliaRecordType(Opportunity opportunity) {
		Map<String, Schema.RecordTypeInfo> recordTypes =
			Schema.SObjectType.Opportunity.getRecordTypeInfosByName();

		if (recordTypes.containsKey('Arelia')) {
			opportunity.RecordTypeId =
				recordTypes.get('Arelia').getRecordTypeId();
		}
	}

    /**
     * Verifies that comments are trimmed before being stored.
     */
    @IsTest
    static void commentsAreTrimmedAndSaved() {
        Account accountRecord = createAccount();

        Opportunity opportunity = createOpportunity(
            accountRecord.Id,
            STATUS_CLIENT_APPROVED,
            INITIAL_REMARKS
        );

        Test.startTest();

        System.enqueueJob(
            new PaymentTermsClientResponseQueueable(
                opportunity.Id,
                STATUS_CLIENT_CHANGES,
                '  ' + UPDATED_REMARKS + '  '
            )
        );

        Test.stopTest();

        Opportunity actualOpportunity = [
            SELECT
                Payment_Terms_Status__c,
                Payment_Term_Client_Remarks__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];

        System.assertEquals(
            STATUS_CLIENT_CHANGES,
            actualOpportunity.Payment_Terms_Status__c,
            'The client response status should be updated.'
        );

        System.assertEquals(
            UPDATED_REMARKS,
            actualOpportunity.Payment_Term_Client_Remarks__c,
            'Leading and trailing spaces should be removed from remarks.'
        );
    }

    /**
     * Verifies that existing remarks are cleared when the client approves
     * and no new comments are supplied.
     */
    @IsTest
    static void approvalWithoutCommentsClearsRemarks() {
        Account accountRecord = createAccount();

        Opportunity opportunity = createOpportunity(
            accountRecord.Id,
            STATUS_CLIENT_CHANGES,
            INITIAL_REMARKS
        );

        Test.startTest();

        System.enqueueJob(
            new PaymentTermsClientResponseQueueable(
                opportunity.Id,
                STATUS_CLIENT_APPROVED,
                null
            )
        );

        Test.stopTest();

        Opportunity actualOpportunity = [
            SELECT
                Payment_Terms_Status__c,
                Payment_Term_Client_Remarks__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];

        System.assertEquals(
            STATUS_CLIENT_APPROVED,
            actualOpportunity.Payment_Terms_Status__c,
            'The payment terms should be marked as approved.'
        );

        System.assertEquals(
            null,
            actualOpportunity.Payment_Term_Client_Remarks__c,
            'Existing remarks should be cleared after approval.'
        );
    }

    /**
     * Verifies that blank comments also clear remarks for Client Approved.
     */
    @IsTest
    static void approvalWithBlankCommentsClearsRemarks() {
        Account accountRecord = createAccount();

        Opportunity opportunity = createOpportunity(
            accountRecord.Id,
            STATUS_CLIENT_CHANGES,
            INITIAL_REMARKS
        );

        Test.startTest();

        System.enqueueJob(
            new PaymentTermsClientResponseQueueable(
                opportunity.Id,
                STATUS_CLIENT_APPROVED,
                '   '
            )
        );

        Test.stopTest();

        Opportunity actualOpportunity = [
            SELECT
                Payment_Terms_Status__c,
                Payment_Term_Client_Remarks__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];

        System.assertEquals(
            STATUS_CLIENT_APPROVED,
            actualOpportunity.Payment_Terms_Status__c,
            'The status should be updated to Client Approved.'
        );

        System.assertEquals(
            null,
            actualOpportunity.Payment_Term_Client_Remarks__c,
            'Blank comments should clear remarks for an approved response.'
        );
    }

    /**
     * Verifies that existing remarks remain unchanged when comments are blank
     * and the status is not Client Approved.
     */
    @IsTest
    static void blankCommentsForChangeRequestPreserveRemarks() {
        Account accountRecord = createAccount();

        Opportunity opportunity = createOpportunity(
            accountRecord.Id,
            STATUS_CLIENT_APPROVED,
            INITIAL_REMARKS
        );

        Test.startTest();

        System.enqueueJob(
            new PaymentTermsClientResponseQueueable(
                opportunity.Id,
                STATUS_CLIENT_CHANGES,
                null
            )
        );

        Test.stopTest();

        Opportunity actualOpportunity = [
            SELECT
                Payment_Terms_Status__c,
                Payment_Term_Client_Remarks__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];

        System.assertEquals(
            STATUS_CLIENT_CHANGES,
            actualOpportunity.Payment_Terms_Status__c,
            'The status should be updated.'
        );

        System.assertEquals(
            INITIAL_REMARKS,
            actualOpportunity.Payment_Term_Client_Remarks__c,
            'Existing remarks should remain when no new comments are given.'
        );
    }

    /**
     * Verifies the early-return condition when Opportunity Id is null.
     */
    @IsTest
    static void nullOpportunityIdReturnsWithoutError() {
        Test.startTest();

        System.enqueueJob(
            new PaymentTermsClientResponseQueueable(
                null,
                STATUS_CLIENT_APPROVED,
                null
            )
        );

        Test.stopTest();

        System.assert(
            true,
            'Queueable should complete without error for a null Opportunity Id.'
        );
    }

    /**
     * Verifies the early-return condition when the status is null.
     */
    @IsTest
    static void nullStatusReturnsWithoutUpdate() {
        Account accountRecord = createAccount();

        Opportunity opportunity = createOpportunity(
            accountRecord.Id,
            STATUS_CLIENT_CHANGES,
            INITIAL_REMARKS
        );

        Test.startTest();

        System.enqueueJob(
            new PaymentTermsClientResponseQueueable(
                opportunity.Id,
                null,
                UPDATED_REMARKS
            )
        );

        Test.stopTest();

        Opportunity actualOpportunity = [
            SELECT
                Payment_Terms_Status__c,
                Payment_Term_Client_Remarks__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];

        System.assertEquals(
            STATUS_CLIENT_CHANGES,
            actualOpportunity.Payment_Terms_Status__c,
            'Status should remain unchanged when the supplied status is null.'
        );

        System.assertEquals(
            INITIAL_REMARKS,
            actualOpportunity.Payment_Term_Client_Remarks__c,
            'Remarks should remain unchanged when the supplied status is null.'
        );
    }

    /**
     * Verifies the early-return condition when the status contains
     * only whitespace.
     */
    @IsTest
    static void blankStatusReturnsWithoutUpdate() {
        Account accountRecord = createAccount();

        Opportunity opportunity = createOpportunity(
            accountRecord.Id,
            STATUS_CLIENT_CHANGES,
            INITIAL_REMARKS
        );

        Test.startTest();

        System.enqueueJob(
            new PaymentTermsClientResponseQueueable(
                opportunity.Id,
                '   ',
                UPDATED_REMARKS
            )
        );

        Test.stopTest();

        Opportunity actualOpportunity = [
            SELECT
                Payment_Terms_Status__c,
                Payment_Term_Client_Remarks__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];

        System.assertEquals(
            STATUS_CLIENT_CHANGES,
            actualOpportunity.Payment_Terms_Status__c,
            'A blank status should not update the Opportunity.'
        );

        System.assertEquals(
            INITIAL_REMARKS,
            actualOpportunity.Payment_Term_Client_Remarks__c,
            'A blank status should not update remarks.'
        );
    }

    /**
     * Verifies that the Queueable exits when the Opportunity no longer exists.
     */
    @IsTest
    static void deletedOpportunityReturnsWithoutError() {
        Account accountRecord = createAccount();

        Opportunity opportunity = createOpportunity(
            accountRecord.Id,
            STATUS_CLIENT_CHANGES,
            INITIAL_REMARKS
        );

        Id deletedOpportunityId = opportunity.Id;

        delete opportunity;

        Test.startTest();

        System.enqueueJob(
            new PaymentTermsClientResponseQueueable(
                deletedOpportunityId,
                STATUS_CLIENT_APPROVED,
                null
            )
        );

        Test.stopTest();

        Integer opportunityCount = [
            SELECT COUNT()
            FROM Opportunity
            WHERE Id = :deletedOpportunityId
        ];

        System.assertEquals(
            0,
            opportunityCount,
            'The deleted Opportunity should not be returned by the query.'
        );
    }
}