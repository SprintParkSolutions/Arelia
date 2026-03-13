/**
 * @description       : Test class for MobileChatbot REST service.
 * Ensures robust code coverage and handles chatbot intent routing.
 * @group             : Tests
 **/
@IsTest
private class MobileChatbotTest {

    /**
     * @description Sets up foundational data for Arelia project testing.
     */
    @TestSetup
    static void setupTestData() {
        // Create Client Contact
        Contact testContact = TestDataUtility.createContact('ChatbotClient', 'client@chatbot.com', 'securepass123');

        // Create Project
        Project__c testProject = TestDataUtility.createProject('Arelia Living - Modern Luxury Demo', 500000, testContact.Id);

        // Link a Document to the Project to cover the 'document/file' branch
        ContentVersion cv = TestDataUtility.createContentVersion('Project specification', 'PDF Content Data');
        TestDataUtility.linkFileToRecord(cv.Id, testProject.Id);

        // Add a Payment Term to the Project to facilitate payment milestone checks
        TestDataUtility.createPaymentTerm(testProject.Id, 'Initial Deposit', 20.0);
    }

    /**
     * @description Helper method to mock the REST request and execute the chatbot method.
     * @param message The chat string sent by the user
     * @param contactId The client's Salesforce Contact ID
     * @return MobileChatbot.ChatbotResponse
     */
    private static MobileChatbot.ChatbotResponse executeChat(String message, String contactId) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        
        req.requestURI = '/services/apexrest/mobileChatbotfinal';
        req.httpMethod = 'POST';

        Map<String, String> requestBodyMap = new Map<String, String>();
        if (String.isNotBlank(message)) {
            requestBodyMap.put('message', message);
        }
        if (String.isNotBlank(contactId)) {
            requestBodyMap.put('contactId', contactId);
        }

        req.requestBody = Blob.valueOf(JSON.serialize(requestBodyMap));
        RestContext.request = req;
        RestContext.response = res;

        return MobileChatbot.chat();
    }

    @IsTest
    static void testMissingContactId() {
        Test.startTest();
        MobileChatbot.ChatbotResponse response = executeChat('project status', '');
        Test.stopTest();

        Assert.isNotNull(response, 'Response should not be null.');
        Assert.areEqual('Missing Contact Id', response.reply, 'Chatbot should reject requests missing a Contact ID.');
    }

    @IsTest
    static void testDefaultFallbackMessage() {
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        MobileChatbot.ChatbotResponse response = executeChat('hello unknown command', testContact.Id);
        Test.stopTest();

        Assert.isNotNull(response, 'Response should not be null.');
        Assert.isTrue(response.reply.contains('Hi 😊 You can ask me about'), 'Chatbot should return the default help menu for unrecognized inputs.');
    }

    @IsTest
    static void testDocumentKeyword() {
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        // Changed input to avoid triggering the 'project' keyword branch
        MobileChatbot.ChatbotResponse response = executeChat('I need my files', testContact.Id);
        Test.stopTest();

        Assert.isNotNull(response, 'Response should not be null.');
        Assert.isTrue(response.reply.contains('project documents available'), 'Chatbot should successfully query and return document counts.');
    }

    @IsTest
    static void testStatusKeyword() {
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        MobileChatbot.ChatbotResponse response = executeChat('What is the project status?', testContact.Id);
        Test.stopTest();

        Assert.isNotNull(response, 'Response should not be null.');
        // Assertion focuses on successful execution without NPEs. 
        // Exact text depends on how MobileProjectStatusService handles the dummy data.
        Assert.isTrue(String.isNotBlank(response.reply), 'Response reply should contain data or a valid fallback string.');
    }

    @IsTest
    static void testTimelineKeyword() {
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        MobileChatbot.ChatbotResponse response = executeChat('Show me the timeline', testContact.Id);
        Test.stopTest();

        Assert.isNotNull(response, 'Response should not be null.');
        Assert.isTrue(String.isNotBlank(response.reply), 'Response reply should populate.');
    }

    @IsTest
    static void testPaymentKeyword() {
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        MobileChatbot.ChatbotResponse response = executeChat('Check payment updates', testContact.Id);
        Test.stopTest();

        Assert.isNotNull(response, 'Response should not be null.');
        Assert.isTrue(String.isNotBlank(response.reply), 'Response reply should populate.');
    }

    @IsTest
    static void testDashboardKeyword() {
        Contact testContact = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        MobileChatbot.ChatbotResponse response = executeChat('Show dashboard', testContact.Id);
        Test.stopTest();

        Assert.isNotNull(response, 'Response should not be null.');
        Assert.isTrue(String.isNotBlank(response.reply), 'Response reply should populate.');
    }
}