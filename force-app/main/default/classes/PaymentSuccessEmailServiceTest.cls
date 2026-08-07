@isTest
private class PaymentSuccessEmailServiceTest {

    @testSetup
    static void setup() {
        // Setup-object DML only (EmailTemplate, User) - kept in its own transaction
        // so it never mixes with non-setup DML (Contact, Project__c) in the test method.
        TestDataUtility.createSpecificEmailTemplate('Payment_Success_Client', 'Payment Success - Client', 'Payment Received: {ClientName}');
        TestDataUtility.createSpecificEmailTemplate('Payment_Success_Supervisor', 'Payment Success - Supervisor', 'Payment Received: {SupervisorName}');

        User supervisor = TestDataUtility.createSupervisorUser('supTest');
        // Update supervisor user's email so the Project formula field resolves to this value
        supervisor.Email = 'supervisor@example.com';
        update supervisor;
    }

    @isTest
    static void testSendPaymentSuccessEmails_toClientAndSupervisor() {
        User supervisor = [SELECT Id, Email FROM User WHERE Email = 'supervisor@example.com' LIMIT 1];

        // Create test contact (client)
        Contact client = TestDataUtility.createContact('ClientTest', 'clienttest@example.com', 'pass123');

        // Create project with a budget and client; set supervisor lookup (formula reads email)
        Project__c proj = TestDataUtility.createProject('Payment Test Project', 50000, client.Id);
        proj.Supervisor_User__c = supervisor.Id;
        update proj;

        // Create a payment term for the project
        Payment_Term__c term = TestDataUtility.createPaymentTerm(proj.Id, 'First Installment', 10);

        // Build the PaymentTermDetail expected by the service
        PaymentService.PaymentTermDetail detail = new PaymentService.PaymentTermDetail();
        detail.paymentTermId = term.Id;
        detail.projectName = proj.Name;
        detail.customerName = client.LastName;
        detail.customerEmail = client.Email;
        detail.installmentLabel = term.Name;
        detail.percentage = term.Percentage__c;
        detail.amount = (proj.Supervisor_Estimated_Budget__c * term.Percentage__c) / 100;

        Blob receiptPdf = Blob.valueOf('Dummy PDF content');

        Test.startTest();
        // Should not throw and should build two email messages (client + supervisor)
        PaymentSuccessEmailService.sendPaymentSuccessEmails(detail, 'rzp_test_id_123', '01 Jan 2026', client.Id, receiptPdf);
        Test.stopTest();

        // Verify templates were created
        System.assertNotEquals(null, AreliaUtility.getEmailTemplateIdByDeveloperName('Payment_Success_Client'));
        System.assertNotEquals(null, AreliaUtility.getEmailTemplateIdByDeveloperName('Payment_Success_Supervisor'));
    }
}