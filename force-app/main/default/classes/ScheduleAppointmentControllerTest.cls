@IsTest
@SuppressWarnings('PMD.CognitiveComplexity,PMD.MethodNamingConventions')
public class ScheduleAppointmentControllerTest {

    @testSetup
    static void setupData() {
        User supervisor = TestDataUtility.createSupervisorUser('SupUser');
        supervisor.Phone = '555-123-4567';
        update supervisor;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<EmailTemplate> templates = new List<EmailTemplate>();

            EmailTemplate t1 = new EmailTemplate();
            t1.DeveloperName = Label.Arelia_Living_Lead_Site_Visiting_Email_Template;
            t1.Name = 'Lead Appointment Template';
            t1.Subject = 'Lead Visit {{{appointmentDate}}} {{{appointmentType}}}';
            t1.HtmlValue =
                'Hi {{{Recipient.Name}}}, ' +
                'visit on {{{appointmentDate}}} at {{{timeSlot}}}. ' +
                'Type {{{appointmentType}}}. ' +
                'Supervisor {{{Supervisor_User__c.Name}}} / {{{Supervisor_User__c.Email}}} / {{{Supervisor_User__c.Phone}}}. ' +
                'Link {{{appointmentApprovalLink}}}';
            t1.TemplateType = 'text';
            t1.FolderId = UserInfo.getUserId();
            templates.add(t1);

            EmailTemplate t2 = new EmailTemplate();
            t2.DeveloperName = Label.Arelia_Living_Supervisor_Site_Visiting_Email_Template;
            t2.Name = 'Supervisor Appointment Template';
            t2.Subject = 'Supervisor Visit {{{appointmentDate}}} {{{appointmentType}}}';
            t2.HtmlValue =
                'Hi {{{Recipient.Name}}}, lead {{{leadName}}} visit on {{{appointmentDate}}} at {{{timeSlot}}}. ' +
                'Type {{{appointmentType}}}, email {{{leadEmail}}}';
            t2.TemplateType = 'text';
            t2.FolderId = UserInfo.getUserId();
            templates.add(t2);

            insert templates;
        }

        Lead l = TestDataUtility.createLead('Lead');
        l.FirstName = 'Test';
        l.Email = 'test@lead.com';
        l.Project_Request_Submitted__c = true;
        l.Approval_Status__c = 'Approved';
        l.Supervisor_User__c = supervisor.Id;
        update l;
    }

    private static String getAnyValidSlot() {
        List<String> validSlots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
        return validSlots.isEmpty() ? '9AM-10AM' : validSlots[0];
    }

    private static String getAnyValidType() {
        List<String> validTypes = ScheduleAppointmentController.getAppointmentTypesPicklistValues();
        return validTypes.isEmpty() ? 'New' : validTypes[0];
    }

    private static String getFollowupType() {
        List<String> validTypes = ScheduleAppointmentController.getAppointmentTypesPicklistValues();
        for (String val : validTypes) {
            if (val != null && val.toLowerCase().contains('follow')) {
                return val;
            }
        }
        return validTypes.isEmpty() ? 'Followup' : validTypes[0];
    }

    private static Lead createLeadWithSupervisor(String emailValue) {
        User supervisor = [
            SELECT Id
            FROM User
            WHERE Phone = '555-123-4567'
            LIMIT 1
        ];

        Lead l = TestDataUtility.createLead('Lead');
        l.FirstName = 'Extra';
        l.Email = emailValue;
        l.Project_Request_Submitted__c = true;
        l.Approval_Status__c = 'Approved';
        l.Supervisor_User__c = supervisor.Id;
        update l;
        return l;
    }

    @IsTest
    static void testScheduleSuccess_NewAppointment() {
        Lead l = [SELECT Id, Supervisor_User__c FROM Lead LIMIT 1];

        String futureDate = String.valueOf(Date.today().addDays(5));
        String slot = getAnyValidSlot();
        String typeValue = getAnyValidType();

        Test.startTest();
        ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
            l.Id,
            l.Supervisor_User__c,
            futureDate,
            slot,
            typeValue
        );
        Test.stopTest();

        Lead updatedLead = [
            SELECT Appointment_Date__c,
                   Appointment_Time_Slots__c,
                   Appointment_Confirmation_Type__c,
                   Appointment_Sent_date__c,
                   Appointment_Completed__c
            FROM Lead
            WHERE Id = :l.Id
        ];

        System.assertEquals(Date.today().addDays(5), updatedLead.Appointment_Date__c, 'Appointment date should be updated');
        System.assertEquals(slot, updatedLead.Appointment_Time_Slots__c, 'Appointment slot should be updated');
        System.assertEquals(typeValue, updatedLead.Appointment_Confirmation_Type__c, 'Appointment type should be updated');
        System.assertEquals(false, updatedLead.Appointment_Completed__c, 'Appointment completed status should be false');
        System.assertEquals(Date.today(), updatedLead.Appointment_Sent_date__c, 'Appointment sent date should be today');
    }

    @IsTest
    static void testScheduleSuccess_FollowupAppointment() {
        Lead l = [SELECT Id, Supervisor_User__c FROM Lead LIMIT 1];

        String slot = getAnyValidSlot();
        String followupType = getFollowupType();

        Test.startTest();
        ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
            l.Id,
            l.Supervisor_User__c,
            String.valueOf(Date.today().addDays(7)),
            slot,
            followupType
        );
        Test.stopTest();

        Lead updatedLead = [
            SELECT Appointment_Date__c,
                   Appointment_Time_Slots__c,
                   Appointment_Confirmation_Type__c,
                   Appointment_Sent_date__c
            FROM Lead
            WHERE Id = :l.Id
        ];

        System.assertEquals(Date.today().addDays(7), updatedLead.Appointment_Date__c, 'Appointment date should be updated');
        System.assertEquals(slot, updatedLead.Appointment_Time_Slots__c, 'Appointment slot should be updated');
        System.assertEquals(followupType, updatedLead.Appointment_Confirmation_Type__c, 'Appointment type should be updated');
        System.assertEquals(Date.today(), updatedLead.Appointment_Sent_date__c, 'Appointment sent date should be today');
    }

    @IsTest
    static void testSlotConflict() {
        Lead l1 = [SELECT Id, Supervisor_User__c FROM Lead LIMIT 1];
        String conflictSlot = getAnyValidSlot();

        TestDataUtility.AppointmentLeadParams conflictParams = new TestDataUtility.AppointmentLeadParams();
        conflictParams.supervisorId = l1.Supervisor_User__c;
        conflictParams.status = 'Approved';
        conflictParams.apptDate = Date.today().addDays(3);
        conflictParams.slot = conflictSlot;
        Lead l2 = TestDataUtility.createAppointmentLead(conflictParams);

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                l1.Id,
                l1.Supervisor_User__c,
                String.valueOf(Date.today().addDays(3)),
                conflictSlot,
                getAnyValidType()
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Scheduling should fail due to slot conflict');
    }

    @IsTest
    static void testInputValidationMissingFields() {
        Lead l = [SELECT Id, Supervisor_User__c FROM Lead LIMIT 1];
        String validSlot = getAnyValidSlot();

        Test.startTest();

        Boolean missingDateThrown = false;
        try {
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                l.Id, l.Supervisor_User__c, null, validSlot, getAnyValidType()
            );
        } catch (AuraHandledException e) {
            missingDateThrown = true;
        }

        Boolean missingSlotThrown = false;
        try {
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                l.Id, l.Supervisor_User__c, String.valueOf(Date.today().addDays(2)), null, getAnyValidType()
            );
        } catch (AuraHandledException e) {
            missingSlotThrown = true;
        }

        Boolean missingTypeThrown = false;
        try {
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                l.Id, l.Supervisor_User__c, String.valueOf(Date.today().addDays(2)), validSlot, null
            );
        } catch (AuraHandledException e) {
            missingTypeThrown = true;
        }

        Test.stopTest();

        System.assertEquals(true, missingDateThrown, 'Scheduling should fail due to missing date');
        System.assertEquals(true, missingSlotThrown, 'Scheduling should fail due to missing time slot');
        System.assertEquals(true, missingTypeThrown, 'Scheduling should fail due to missing appointment type');
    }

    @IsTest
    static void testInputValidationPastDate() {
        Lead l = [SELECT Id, Supervisor_User__c FROM Lead LIMIT 1];

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                l.Id,
                l.Supervisor_User__c,
                String.valueOf(Date.today().addDays(-1)),
                getAnyValidSlot(),
                getAnyValidType()
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Scheduling should fail due to past date');
    }

    @IsTest
    static void testDataValidationMissingSupervisor() {
        Lead orphanedLead = TestDataUtility.createLead('Orphan');
        orphanedLead.Email = 'orphan@test.com';
        update orphanedLead;

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                orphanedLead.Id,
                null,
                String.valueOf(Date.today().addDays(2)),
                getAnyValidSlot(),
                getAnyValidType()
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Scheduling should fail due to missing supervisor');
    }

    @IsTest
    static void testDataValidationMissingLeadEmail() {
        Lead l = createLeadWithSupervisor(null);

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                l.Id,
                l.Supervisor_User__c,
                String.valueOf(Date.today().addDays(4)),
                getAnyValidSlot(),
                getAnyValidType()
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Scheduling should fail due to missing lead email');
    }

    @IsTest
    static void testTodayInvalidTimeFormat() {
        Lead l = createLeadWithSupervisor('badformat@test.com');

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                l.Id,
                l.Supervisor_User__c,
                String.valueOf(Date.today()),
                'INVALID_SLOT',
                getAnyValidType()
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Scheduling should fail due to invalid time slot format');
    }

    @IsTest
    static void testTodayPastTimeSlot() {
        Lead l = createLeadWithSupervisor('pastslot@test.com');

        Test.startTest();
        Boolean exceptionThrown = false;
        try {
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                l.Id,
                l.Supervisor_User__c,
                String.valueOf(Date.today()),
                '12AM-1AM',
                getAnyValidType()
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown, 'Scheduling should fail due to past time slot');
    }

    @IsTest
    static void testPicklistHelpers() {
        Test.startTest();
        List<String> slots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
        List<String> types = ScheduleAppointmentController.getAppointmentTypesPicklistValues();
        Test.stopTest();

        System.assertNotEquals(null, slots, 'Time slots picklist values should be returned');
        System.assertNotEquals(null, types, 'Appointment types picklist values should be returned');
    }
}