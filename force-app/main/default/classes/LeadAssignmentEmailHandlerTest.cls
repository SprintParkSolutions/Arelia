/**
 * @description       : Test class for LeadAssignmentEmailHandler
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             :
 * @last modified on  : 01-16-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@IsTest
public class LeadAssignmentEmailHandlerTest {

    // Ideally, the Label name matches the DeveloperName.
    private static final String TEMPLATE_DEV_NAME = 'Arelia_Living_Supervisor_Email_Template';

    @TestSetup
    static void setup() {
        // 1. Create Supervisor Users using Utility
        // No need to store in variables if not used in this method
        TestDataUtility.createSupervisorUser('sup1');
        TestDataUtility.createSupervisorUser('sup2');

        // 2. Create Email Template matching the Label expected by the Handler
        System.runAs(new User(Id = UserInfo.getUserId())) {
            EmailTemplate tpl = new EmailTemplate(
                DeveloperName = TEMPLATE_DEV_NAME,
                Name = 'Test Supervisor Template',
                Subject = 'Lead Assigned: {{{Lead.Name}}}',
                HtmlValue = '<html><body>New Lead: {{{Lead.Name}}}</body></html>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId(),
                IsActive = true
            );
            insert tpl;
        }
    }

    // ==========================================
    // HELPER METHOD
    // ==========================================
    private static String getFakeId(Schema.SObjectType sot) {
        String result = String.valueOf(sot.getDescribe().getKeyPrefix());
        return result + '000000000001';
    }

    // ==========================================
    // POSITIVE TESTS
    // ==========================================

    @IsTest
    static void testHandleSupervisorAssignmentNewAssignment() {
        User sup1 = [SELECT Id, Email FROM User WHERE Alias = 'sup1' LIMIT 1];

        // 1. Create Lead using Utility
        Lead l = TestDataUtility.createLead('Test Lead');

        // Create Old Map (Supervisor is null)
        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => l.clone(true, true, true, true) };

        // 2. Update Lead with Supervisor AND REQUIRED APPROVAL FIELDS
        l.Supervisor_User__c = sup1.Id;
        l.Appointment_Status__c = 'Approved';
        l.Project_Request_Submitted__c = true; // Fix: Added to satisfy validation rule
        l.Approval_Status__c = 'Approved';     // Fix: Satisfy Validation Rule
        update l;

        // 3. RE-QUERY to ensure Formula Field (Supervisor_User_Email__c) is calculated
        Lead updatedLead = [SELECT Id, Supervisor_User__c, Supervisor_User_Email__c, Appointment_Status__c FROM Lead WHERE Id = :l.Id];

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            LeadAssignmentEmailHandler.handleSupervisorAssignment(
                new List<Lead>{ updatedLead },
                oldMap
            );
            Integer invocations = Limits.getEmailInvocations();
            Test.stopTest();

            Assert.areEqual(1, invocations, 'An email should be sent when a supervisor is newly assigned.');
        }
    }

    // ==========================================
    // NEGATIVE LOGIC TESTS
    // ==========================================

    @IsTest
    static void testHandleSupervisorAssignmentChangeSupervisor() {
        User sup1 = [SELECT Id FROM User WHERE Alias = 'sup1' LIMIT 1];
        User sup2 = [SELECT Id FROM User WHERE Alias = 'sup2' LIMIT 1];

        // 1. Create Lead using Utility
        TestDataUtility.AppointmentLeadParams params = new TestDataUtility.AppointmentLeadParams();
        params.supervisorId = sup1.Id;
        params.status = 'Approved';
        params.apptDate = Date.today();
        params.slot = '9AM-10AM';

        Lead l = TestDataUtility.createAppointmentLead(params);

        // 2. Create Old Map (Supervisor was sup1)
        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => l.clone(true, true, true, true) };

        // 3. Update to Sup2 AND REQUIRED APPROVAL FIELDS
        l.Supervisor_User__c = sup2.Id;
        l.Project_Request_Submitted__c = true; // Fix: Added to satisfy validation rule
        l.Approval_Status__c = 'Approved';
        update l;

        Lead updatedLead = [SELECT Id, Supervisor_User__c, Supervisor_User_Email__c FROM Lead WHERE Id = :l.Id];

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            LeadAssignmentEmailHandler.handleSupervisorAssignment(
                new List<Lead>{ updatedLead },
                oldMap
            );
            Integer invocations = Limits.getEmailInvocations();
            Test.stopTest();

            Assert.areEqual(0, invocations, 'Should NOT send email if changing from one supervisor to another (only new assignments).');
        }
    }

    @IsTest
    static void testHandleSupervisorAssignmentNoChange() {
        User sup1 = [SELECT Id FROM User WHERE Alias = 'sup1' LIMIT 1];

        // 1. Create Lead with Supervisor
        TestDataUtility.AppointmentLeadParams params = new TestDataUtility.AppointmentLeadParams();
        params.supervisorId = sup1.Id;
        params.status = 'Approved';
        Lead l = TestDataUtility.createAppointmentLead(params);

        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => l.clone(true, true, true, true) };

        // 2. Update irrelevant field
        l.Company = 'Changed Co';

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            LeadAssignmentEmailHandler.handleSupervisorAssignment(
                new List<Lead>{ l },
                oldMap
            );
            Integer invocations = Limits.getEmailInvocations();
            Test.stopTest();

            Assert.areEqual(0, invocations, 'Should NOT send email if supervisor did not change.');
        }
    }

    @IsTest
    static void testHandleSupervisorAssignmentChangeToNull() {
        User sup1 = [SELECT Id FROM User WHERE Alias = 'sup1' LIMIT 1];

        TestDataUtility.AppointmentLeadParams params = new TestDataUtility.AppointmentLeadParams();
        params.supervisorId = sup1.Id;
        Lead l = TestDataUtility.createAppointmentLead(params);

        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => l.clone(true, true, true, true) };

        // Update to Null AND REQUIRED APPROVAL FIELDS
        l.Supervisor_User__c = null;
        l.Project_Request_Submitted__c = true; // Fix: Added to satisfy validation rule
        l.Approval_Status__c = 'Approved';
        update l;

        Lead updatedLead = [SELECT Id, Supervisor_User__c, Supervisor_User_Email__c FROM Lead WHERE Id = :l.Id];

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            LeadAssignmentEmailHandler.handleSupervisorAssignment(
                new List<Lead>{ updatedLead },
                oldMap
            );
            Integer invocations = Limits.getEmailInvocations();
            Test.stopTest();

            Assert.areEqual(0, invocations, 'Should NOT send email if supervisor is removed.');
        }
    }

    @IsTest
    static void testFetchTemplateErrorHandling() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            LeadAssignmentEmailHandler.handleSupervisorAssignment(new List<Lead>(), new Map<Id, Lead>());
            Test.stopTest();

            Assert.areEqual(0, Limits.getEmailInvocations(), 'No emails should be sent for empty input lists');
        }
    }

    // ==========================================
    // EXCEPTION & EDGE CASE TESTS
    // ==========================================

    @IsTest
    static void testHandleSupervisorAssignmentMissingTemplate() {
        User sup1 = [SELECT Id FROM User WHERE Alias = 'sup1' LIMIT 1];

        // 1. Delete the template created in setup to force getEmailTemplate() to return null
        EmailTemplate tpl = [SELECT Id FROM EmailTemplate WHERE DeveloperName = :TEMPLATE_DEV_NAME LIMIT 1];
        delete tpl;

        // 2. Prepare Data using local getFakeId to avoid DB inserts (and avoid validation rules!)
        Lead l = new Lead(Id = getFakeId(Lead.SObjectType), Supervisor_User__c = sup1.Id);
        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => new Lead(Id = l.Id, Supervisor_User__c = null) };

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            LeadAssignmentEmailHandler.handleSupervisorAssignment(
                new List<Lead>{ l },
                oldMap
            );
            Integer invocations = Limits.getEmailInvocations();
            Test.stopTest();

            Assert.areEqual(0, invocations, 'Should return early (no email) if template is missing.');
        }
    }

    @IsTest
    static void testHandleSupervisorAssignmentSupervisorNoEmail() {
        User sup1 = [SELECT Id FROM User WHERE Alias = 'sup1' LIMIT 1];

        // 1. Use JSON deserialization to force the Formula Field 'Supervisor_User_Email__c' to be NULL
        // while the 'Supervisor_User__c' lookup ID is present.
        String fakeId = getFakeId(Lead.SObjectType);
        String leadJson = '{"attributes":{"type":"Lead"}, "Id":"' + fakeId + '", "Supervisor_User__c":"' + sup1.Id + '", "Supervisor_User_Email__c": null}';
        Lead l = (Lead)JSON.deserialize(leadJson, Lead.class);

        Map<Id, Lead> oldMap = new Map<Id, Lead>{ l.Id => new Lead(Id = l.Id, Supervisor_User__c = null) };

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            LeadAssignmentEmailHandler.handleSupervisorAssignment(
                new List<Lead>{ l },
                oldMap
            );
            Integer invocations = Limits.getEmailInvocations();
            Test.stopTest();

            Assert.areEqual(0, invocations, 'Should not send email if supervisor email is blank/null.');
        }
    }

    @IsTest
    static void testSendEmailFailure() {
        User sup1 = [SELECT Id FROM User WHERE Alias = 'sup1' LIMIT 1];

        // 1. Prepare Data with NULL ID to cause Messaging.sendEmail failure
        // We do NOT provide an "Id" field in the JSON. This results in a Lead object with Id=null.
        // We DO provide Supervisor Email to pass the first check in buildEmail().
        String leadJson = '{ ' +
            '"attributes": {"type": "Lead"}, ' +
            '"Supervisor_User__c": "' + sup1.Id + '", ' +
            '"Supervisor_User_Email__c": "test@test.com" ' +
        '}';

        Lead leadWithNullId = (Lead)JSON.deserialize(leadJson, Lead.class);

        // 2. Setup Map with NULL key to ensure logic proceeds
        Map<Id, Lead> oldMap = new Map<Id, Lead>();
        oldMap.put(null, new Lead(Supervisor_User__c = null));

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            try {
                // This should invoke buildEmail (success) and then sendEmails (failure due to null Id/TargetObject)
                LeadAssignmentEmailHandler.handleSupervisorAssignment(
                    new List<Lead>{ leadWithNullId },
                    oldMap
                );
                Assert.fail('Should have thrown AuraHandledException due to send failure');
            } catch (Exception e) {
                // Expected behavior: Handler catches MessagingException or validation error and rethrows AuraHandledException
                Boolean isExpectedException = e.getTypeName().contains('AuraHandledException') ||
                                              e.getMessage().contains('Script-thrown') ||
                                              e.getMessage().contains('Email failed');
                Assert.isTrue(isExpectedException, 'Should catch the handled exception from sendEmails. Actual: ' + e.getMessage());
            }
            Test.stopTest();
        }
    }
}