/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 02-06-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@isTest
private class PaymentTermRestServiceTest {

    @testSetup
    static void setupData() {
        // Create baseline data for the general success test
        Contact testContact = TestDataUtility.createContact('Doe', 'john@test.com', 'pass123');
        Project__c proj = TestDataUtility.createProject('Standard_Project', 50000, testContact.Id);
        
        // These terms are created manually here. 
        // If automation also creates 3, this project will have 6 total.
        TestDataUtility.createPaymentTerm(proj.Id, 'Initial Deposit', 20.0);
        TestDataUtility.createPaymentTerm(proj.Id, 'Midway Payment', 30.0);
        TestDataUtility.createPaymentTerm(proj.Id, 'Final Settlement', 50.0);
    }

    /**
     * @description Tests retrieval of terms for a project. 
     * Uses dynamic count to account for org-level automation.
     */
    @isTest
    static void testGetTermsSuccess() {
        // Retrieve actual count from DB to handle any background automation
        Integer expectedCount = [SELECT COUNT() FROM Payment_Term__c WHERE Project__r.Name = 'Standard_Project'];

        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/payment-terms';
        request.httpMethod = 'GET';
        request.addParameter('projectName', 'Standard_Project');
        RestContext.request = request;

        Test.startTest();
        List<PaymentTermRestService.PaymentTermDTO> results = PaymentTermRestService.getTerms();
        Test.stopTest();

        System.assertNotEquals(null, results, 'Result list should not be null');
        System.assertEquals(expectedCount, results.size(), 'Should return all terms associated with this project name');
    }

    /**
     * @description Tests the empty projectName parameter scenario.
     */
    @isTest
    static void testGetTermsEmptyProjectName() {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/payment-terms';
        request.httpMethod = 'GET';
        // No parameter added
        RestContext.request = request;

        Test.startTest();
        List<PaymentTermRestService.PaymentTermDTO> results = PaymentTermRestService.getTerms();
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return 0 terms for a blank project name');
    }

    /**
     * @description Tests a project name that does not exist in the system.
     */
    @isTest
    static void testGetTermsNoMatchingProject() {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/payment-terms';
        request.httpMethod = 'GET';
        request.addParameter('projectName', 'Non_Existent_Project_XYZ');
        RestContext.request = request;

        Test.startTest();
        List<PaymentTermRestService.PaymentTermDTO> results = PaymentTermRestService.getTerms();
        Test.stopTest();

        // This should ALWAYS be 0 because this project name doesn't exist to trigger any automation
        System.assertEquals(0, results.size(), 'Should return 0 for a project name that does not exist');
    }
}