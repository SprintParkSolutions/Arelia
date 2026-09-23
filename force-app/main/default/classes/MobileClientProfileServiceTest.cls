/**
 * @description       : Test class for MobileClientProfileService
 * @author            : AI Assistant
 * @group             : Tests
 * @last modified on  : 03-30-2026
 **/
@isTest
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveAsserts') // PMD sometimes misses the modern Assert class usage
private class MobileClientProfileServiceTest {

    @TestSetup
    static void setupTestData() {
        // 1. Create a Test Contact using the provided Utility
        Contact testContact = TestDataUtility.createContact('Doe', 'johndoe@testorg.com', 'TestPass123!');
        
        // 2. Create a Test Project using the provided Utility
        TestDataUtility.createProject('Alpha Renovation', 50000.00, testContact.Id);
        
        // 3. Create Test Cases (Not in utility, so we create them here)
        List<Case> testCases = new List<Case>{
            new Case(
                ContactId = testContact.Id,
                Subject = 'Issue with installation',
                Description = 'The front door is squeaking.',
                Status = 'New',
                Priority = 'High',
                Type = 'Problem'
            ),
            new Case(
                ContactId = testContact.Id,
                Subject = 'Billing inquiry',
                Description = 'Question about the latest invoice.',
                Status = 'Closed',
                Priority = 'Medium',
                Type = 'Question'
            )
        };
        insert testCases;
    }

    @isTest
    static void testGetClientProfile_Success() {
        // Arrange
        Contact testContact = [SELECT Id, LastName, Email FROM Contact LIMIT 1];
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobileClientProfile';
        req.httpMethod = 'POST';
        // Construct standard JSON body
        req.requestBody = Blob.valueOf('{"contactId": "' + testContact.Id + '"}');
        
        RestContext.request = req;
        RestContext.response = new RestResponse();

        // Act
        Test.startTest();
        MobileClientProfileService.ResponseDTO response = MobileClientProfileService.getClientProfile();
        Test.stopTest();

        // Assert
        Assert.isTrue(response.success, 'The API call should be successful.');
        Assert.areEqual('Success', response.message, 'Message should be Success.');
        
        // Verify User Data
        Assert.isNotNull(response.user, 'User DTO should be populated.');
        Assert.areEqual(testContact.LastName, response.user.name, 'User name should match the contact last name.');
        Assert.areEqual(testContact.Email, response.user.email, 'User email should match.');
        Assert.areEqual('Alpha Renovation', response.user.projectName, 'Project name should match.');
        
        // Verify Case Data
        Assert.isNotNull(response.cases, 'Cases list should not be null.');
        Assert.areEqual(2, response.cases.size(), 'Should return exactly 2 cases.');
        Assert.areEqual('Issue with installation', response.cases[0].subject, 'Cases should be ordered properly or mapped correctly.');
    }

    @isTest
    static void testGetClientProfile_MissingContactId() {
        // Arrange
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobileClientProfile';
        req.httpMethod = 'POST';
        // Construct JSON body with an empty contactId
        req.requestBody = Blob.valueOf('{"contactId": ""}');
        
        RestContext.request = req;
        RestContext.response = new RestResponse();

        // Act
        Test.startTest();
        MobileClientProfileService.ResponseDTO response = MobileClientProfileService.getClientProfile();
        Test.stopTest();

        // Assert
        Assert.isFalse(response.success, 'The API call should fail due to missing ID.');
        Assert.areEqual('Missing Contact Id', response.message, 'Should return the missing ID error message.');
        Assert.isTrue(response.cases.isEmpty(), 'Cases list should be empty.');
    }

    @isTest
    static void testGetClientProfile_NullBody() {
        // Arrange
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobileClientProfile';
        req.httpMethod = 'POST';
        // Completely null request body
        req.requestBody = null; 
        
        RestContext.request = req;
        RestContext.response = new RestResponse();

        // Act
        Test.startTest();
        MobileClientProfileService.ResponseDTO response = MobileClientProfileService.getClientProfile();
        Test.stopTest();

        // Assert
        Assert.isFalse(response.success, 'The API call should fail gracefully when body is null.');
        Assert.areEqual('Missing Contact Id', response.message, 'Should fall back to missing ID message when body is empty.');
    }

    @isTest
    static void testGetClientProfile_ExceptionHandling() {
        // Arrange
        // Generate a valid-looking fake ID that does not exist in the database to force a QueryException
        String contactPrefix = Schema.SObjectType.Contact.getKeyPrefix();
        String fakeContactId = contactPrefix + '00000000000AAA'; 
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/mobileClientProfile';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"contactId": "' + fakeContactId + '"}');
        
        RestContext.request = req;
        RestContext.response = new RestResponse();

        // Act
        Test.startTest();
        MobileClientProfileService.ResponseDTO response = MobileClientProfileService.getClientProfile();
        Test.stopTest();

        // Assert
        Assert.isFalse(response.success, 'The API call should fail due to the SOQL exception (Contact not found).');
        Assert.isNotNull(response.message, 'The exception message should be populated.');
        Assert.isTrue(response.message.contains('List has no rows for assignment to SObject'), 'Should catch the specific SOQL error.');
    }
}