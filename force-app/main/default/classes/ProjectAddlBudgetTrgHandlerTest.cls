@IsTest
private class ProjectAddlBudgetTrgHandlerTest {

    private static Project__c withPending(Decimal amount, String reason, String status) {
        Project__c p = new Project__c();
        p.Additional_Request_Status__c = status;
        p.Pending_Additional_Amount__c = amount;
        p.Pending_Additional_Reason__c = reason;
        return p;
    }

    @IsTest
    static void testDispatchesOnCompleteSubmit() {
        // Normal submitRequest() path: status, amount and reason all set together in one update.
        Project__c oldProj = withPending(null, null, null);
        Project__c newProj = withPending(500, 'Extra tiles cost', 'Pending');

        Boolean result = ProjectAdditionalBudgetTriggerHandler.shouldDispatchEmail(
            newProj, oldProj, oldProj.Additional_Request_Status__c, newProj.Additional_Request_Status__c
        );

        System.assertEquals(true, result, 'A complete first-time Pending submission should dispatch the email.');
    }

    @IsTest
    static void testDoesNotDispatchWhenStatusSetBeforeDataIsComplete() {
        // The mobile app sets Additional_Request_Status__c = 'Pending' before amount/reason are
        // filled in. Dispatching here would send a manager email with blank request details.
        Project__c oldProj = withPending(null, null, null);
        Project__c newProj = withPending(null, null, 'Pending');

        Boolean result = ProjectAdditionalBudgetTriggerHandler.shouldDispatchEmail(
            newProj, oldProj, oldProj.Additional_Request_Status__c, newProj.Additional_Request_Status__c
        );

        System.assertEquals(false, result, 'An incomplete Pending transition should not dispatch a premature email.');
    }

    @IsTest
    static void testDispatchesWhenDataCompletedInLaterUpdateWhileAlreadyPending() {
        // Reproduces the reported bug: a prior update already set status to 'Pending' with blank
        // data. A later, separate update fills in the real amount/reason but never touches status
        // again - this is the update that must trigger the manager email.
        Project__c oldProj = withPending(null, null, 'Pending');
        Project__c newProj = withPending(10000, 'Small changes in the layout', 'Pending');

        Boolean result = ProjectAdditionalBudgetTriggerHandler.shouldDispatchEmail(
            newProj, oldProj, oldProj.Additional_Request_Status__c, newProj.Additional_Request_Status__c
        );

        System.assertEquals(
            true,
            result,
            'Completing the pending amount/reason while status is unchanged must still dispatch the manager email.'
        );
    }

    @IsTest
    static void testDoesNotDispatchWhenNothingRelevantChangedWhilePending() {
        Project__c oldProj = withPending(10000, 'Small changes in the layout', 'Pending');
        Project__c newProj = withPending(10000, 'Small changes in the layout', 'Pending');

        Boolean result = ProjectAdditionalBudgetTriggerHandler.shouldDispatchEmail(
            newProj, oldProj, oldProj.Additional_Request_Status__c, newProj.Additional_Request_Status__c
        );

        System.assertEquals(false, result, 'An unrelated update while already Pending should not re-dispatch the email.');
    }

    @IsTest
    static void testDispatchesOnApprovedTransition() {
        Project__c oldProj = withPending(10000, 'Small changes in the layout', 'Pending');
        Project__c newProj = withPending(null, null, 'Approved');

        Boolean result = ProjectAdditionalBudgetTriggerHandler.shouldDispatchEmail(
            newProj, oldProj, oldProj.Additional_Request_Status__c, newProj.Additional_Request_Status__c
        );

        System.assertEquals(true, result, 'An Approved transition should always dispatch, unchanged from prior behavior.');
    }

    @IsTest
    static void testDispatchesOnRejectedTransition() {
        Project__c oldProj = withPending(10000, 'Small changes in the layout', 'Pending');
        Project__c newProj = withPending(null, null, 'Rejected');

        Boolean result = ProjectAdditionalBudgetTriggerHandler.shouldDispatchEmail(
            newProj, oldProj, oldProj.Additional_Request_Status__c, newProj.Additional_Request_Status__c
        );

        System.assertEquals(true, result, 'A Rejected transition should always dispatch, unchanged from prior behavior.');
    }
}