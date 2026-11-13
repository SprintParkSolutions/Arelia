/**
 * -----------------------------------------------------------------------------
 * Class Name      : ProspectSupervisorInfoApiTest
 * Author          : Arelia
 * Created Date    : Oct 6, 2026
 * Last Modified By: Arelia
 * Last Modified On: Oct 6, 2026
 * Description     : Test class for ProspectSupervisorInfoApi.
 * -----------------------------------------------------------------------------
 */
@IsTest
private class ProspectSupervisorInfoApiTest {

    private static final String TEST_EMAIL = 'supervisor.test@example.com';
    private static final String TEST_PHONE = '9876543210';
    private static final String ASSIGNED_LEAD = 'Assigned Client';
    private static final String UNASSIGNED_LEAD = 'Unassigned Client';

    @TestSetup
    static void setupData() {
        User supervisor = createSupervisorUser();
        insert supervisor;

        Lead assignedLead = createLead(ASSIGNED_LEAD);
        assignedLead.Supervisor_User__c = supervisor.Id;

        Lead unassignedLead = createLead(UNASSIGNED_LEAD);

        insert new List<Lead>{
            assignedLead,
            unassignedLead
        };
    }

    @IsTest
    static void getSupervisorReturnsAssignedSupervisor() {
        Lead testLead = [
            SELECT Id,
                   Supervisor_User__c,
                   Supervisor_User__r.Name,
                   Supervisor_User_Email__c,
                   Supervisor_User_Phone__c
            FROM Lead
            WHERE LastName = :ASSIGNED_LEAD
            LIMIT 1
        ];

        prepareRequest(String.valueOf(testLead.Id));

        Test.startTest();
        ProspectSupervisorInfoApi.SupervisorResponse response =
            ProspectSupervisorInfoApi.getSupervisor();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Assigned supervisor request should return HTTP 200.'
        );
        System.assertEquals(
            true,
            response.success,
            'Response should be successful.'
        );
        System.assertEquals(
            testLead.Id,
            response.leadId,
            'Response should contain the requested Lead Id.'
        );
        System.assertEquals(
            true,
            response.assigned,
            'Supervisor should be marked as assigned.'
        );
        System.assertEquals(
            testLead.Supervisor_User__c,
            response.supervisorUserId,
            'Supervisor User Id should match the Lead.'
        );
        System.assertEquals(
            testLead.Supervisor_User__r.Name,
            response.supervisorUser,
            'Supervisor name should match.'
        );
        System.assertEquals(
            testLead.Supervisor_User_Email__c,
            response.supervisorUserEmail,
            'Supervisor email should match the Lead formula field.'
        );
        System.assertEquals(
            testLead.Supervisor_User_Phone__c,
            response.supervisorUserPhone,
            'Supervisor phone should match the Lead formula field.'
        );
        System.assertEquals(
            'Supervisor information loaded.',
            response.message,
            'Success message should match.'
        );
    }

    @IsTest
    static void getSupervisorReturnsUnassignedLead() {
        Lead testLead = [
            SELECT Id
            FROM Lead
            WHERE LastName = :UNASSIGNED_LEAD
            LIMIT 1
        ];

        prepareRequest(String.valueOf(testLead.Id));

        Test.startTest();
        ProspectSupervisorInfoApi.SupervisorResponse response =
            ProspectSupervisorInfoApi.getSupervisor();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Unassigned supervisor request should return HTTP 200.'
        );
        System.assertEquals(
            true,
            response.success,
            'Valid Lead request should be successful.'
        );
        System.assertEquals(
            testLead.Id,
            response.leadId,
            'Lead Id should match.'
        );
        System.assertEquals(
            false,
            response.assigned,
            'Supervisor should not be marked as assigned.'
        );
        System.assertEquals(
            null,
            response.supervisorUserId,
            'Supervisor User Id should be null.'
        );
        System.assertEquals(
            null,
            response.supervisorUser,
            'Supervisor name should be null.'
        );
        System.assertEquals(
            null,
            response.supervisorUserEmail,
            'Supervisor email should be null.'
        );
        System.assertEquals(
            null,
            response.supervisorUserPhone,
            'Supervisor phone should be null.'
        );
        System.assertEquals(
            'A supervisor has not been assigned yet.',
            response.message,
            'Unassigned message should match.'
        );
    }

    @IsTest
    static void getSupervisorReturns400ForMissingLeadId() {
        prepareRequest(null);

        Test.startTest();
        ProspectSupervisorInfoApi.SupervisorResponse response =
            ProspectSupervisorInfoApi.getSupervisor();
        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Missing Lead Id should return HTTP 400.'
        );
        System.assertEquals(
            false,
            response.success,
            'Response should not be successful.'
        );
        System.assertEquals(
            'A valid Salesforce Lead ID is required.',
            response.message,
            'Validation message should match.'
        );
    }

    @IsTest
    static void getSupervisorReturns400ForBlankLeadId() {
        prepareRequest('   ');

        Test.startTest();
        ProspectSupervisorInfoApi.SupervisorResponse response =
            ProspectSupervisorInfoApi.getSupervisor();
        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Blank Lead Id should return HTTP 400.'
        );
        System.assertEquals(
            false,
            response.success,
            'Response should not be successful.'
        );
        System.assertEquals(
            'A valid Salesforce Lead ID is required.',
            response.message,
            'Validation message should match.'
        );
    }

    @IsTest
    static void getSupervisorReturns400ForInvalidLeadId() {
        prepareRequest('INVALID-ID');

        Test.startTest();
        ProspectSupervisorInfoApi.SupervisorResponse response =
            ProspectSupervisorInfoApi.getSupervisor();
        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'Invalid Salesforce Id should return HTTP 400.'
        );
        System.assertEquals(
            false,
            response.success,
            'Response should not be successful.'
        );
        System.assertEquals(
            'A valid Salesforce Lead ID is required.',
            response.message,
            'Validation message should match.'
        );
    }

    @IsTest
    static void getSupervisorReturns400ForNonLeadId() {
        Account testAccount = new Account(
            Name = 'Supervisor API Test Account'
        );
        insert testAccount;

        prepareRequest(String.valueOf(testAccount.Id));

        Test.startTest();
        ProspectSupervisorInfoApi.SupervisorResponse response =
            ProspectSupervisorInfoApi.getSupervisor();
        Test.stopTest();

        System.assertEquals(
            400,
            RestContext.response.statusCode,
            'A non-Lead Salesforce Id should return HTTP 400.'
        );
        System.assertEquals(
            false,
            response.success,
            'Response should not be successful.'
        );
        System.assertEquals(
            'A valid Salesforce Lead ID is required.',
            response.message,
            'Validation message should match.'
        );
    }

    @IsTest
    static void getSupervisorHandlesWhitespaceInLeadId() {
        Lead testLead = [
            SELECT Id
            FROM Lead
            WHERE LastName = :UNASSIGNED_LEAD
            LIMIT 1
        ];

        prepareRequest(
            '  ' + String.valueOf(testLead.Id) + '  '
        );

        Test.startTest();
        ProspectSupervisorInfoApi.SupervisorResponse response =
            ProspectSupervisorInfoApi.getSupervisor();
        Test.stopTest();

        System.assertEquals(
            200,
            RestContext.response.statusCode,
            'Lead Id containing whitespace should return HTTP 200.'
        );
        System.assertEquals(
            true,
            response.success,
            'Trimmed Lead Id should be processed successfully.'
        );
        System.assertEquals(
            testLead.Id,
            response.leadId,
            'Correct Lead should be returned.'
        );
    }

    private static void prepareRequest(String leadId) {
        RestRequest request = new RestRequest();
        request.requestUri =
            '/services/apexrest/registration/lead/supervisor';
        request.httpMethod = 'GET';

        if (leadId != null) {
            request.addParameter('leadId', leadId);
        }

        RestContext.request = request;
        RestContext.response = new RestResponse();
    }

    private static Lead createLead(String lastName) {
        return new Lead(
            FirstName = 'Test',
            LastName = lastName,
            Company = 'Arelia Test'
        );
    }

    private static User createSupervisorUser() {
        String uniqueValue =
            String.valueOf(DateTime.now().getTime());

        return new User(
            FirstName = 'Test',
            LastName = 'Supervisor',
            Alias = 'tsup',
            Email = TEST_EMAIL,
            Phone = TEST_PHONE,
            Username =
                'supervisor.' + uniqueValue + '@example.com',
            CommunityNickname =
                'supervisor' + uniqueValue,
            TimeZoneSidKey = 'Asia/Kolkata',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId()
        );
    }
}