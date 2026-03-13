/**
 * @description       : Test class for ScheduleAppointmentController
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             :
 * @last modified on  : 01-23-2026
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
@IsTest
public class ScheduleAppointmentControllerTest {

    @TestSetup
    static void setupData() {
        // 1. Create Supervisor User via Utility
        User supervisor = TestDataUtility.createSupervisorUser('SupUser');
        // Ensure Supervisor has the required Phone field populated for validation
        supervisor.Phone = '555-123-4567';
        update supervisor;

        // 2. Create Email Templates via Utility (in runAs to avoid Mixed DML)
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Lead Template
            TestDataUtility.createSpecificEmailTemplate(
                Label.Arelia_Living_Lead_Site_Visiting_Email_Template,
                'Lead Template',
                'Lead Visit {{{appointmentDate}}}'
            );

            // Supervisor Template
            TestDataUtility.createSpecificEmailTemplate(
                Label.Arelia_Living_Supervisor_Site_Visiting_Email_Template,
                'Supervisor Template',
                'Sup Visit {{{appointmentDate}}}'
            );
        }

        // 3. Create Lead via Utility
        TestDataUtility.AppointmentLeadParams leadParams = new TestDataUtility.AppointmentLeadParams();
        leadParams.supervisorId = supervisor.Id;
        leadParams.status = 'Pending';
        leadParams.apptDate = null; // Not scheduled yet
        leadParams.slot = null;
        // Note: The utility bypasses duplicate rules, ensuring safe insertion
        TestDataUtility.createAppointmentLead(leadParams);
    }

    @IsTest
    static void testScheduleSuccess() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Lead testLead = [SELECT Id, Supervisor_User__c FROM Lead LIMIT 1];

            String futureDate = String.valueOf(Date.today().addDays(5));

            List<String> validSlots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
            List<String> validTypes = ScheduleAppointmentController.getAppointmentTypesPicklistValues();

            String slot = validSlots.isEmpty() ? '9AM-10AM' : validSlots[0];
            String type = validTypes.isEmpty() ? 'In Person' : validTypes[0];

            Test.startTest();
            ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                testLead.Id,
                testLead.Supervisor_User__c,
                futureDate,
                slot,
                type
            );
            Test.stopTest();

            // Verify Lead was updated
            Lead updatedLead = [SELECT Appointment_Date__c, Appointment_Time_Slots__c, Appointment_Confirmation_Type__c, Appointment_Sent_date__c FROM Lead WHERE Id = :testLead.Id];
            System.assertEquals(Date.today().addDays(5), updatedLead.Appointment_Date__c, 'Appointment Date should be updated to future date');
            System.assertEquals(slot, updatedLead.Appointment_Time_Slots__c, 'Time Slot should be updated');
            System.assertEquals(type, updatedLead.Appointment_Confirmation_Type__c, 'Confirmation Type should be updated');
            System.assertEquals(System.today(), updatedLead.Appointment_Sent_date__c, 'Sent Date should be today');
        }
    }

    @IsTest
    static void testSlotConflict() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Lead existingLead = [SELECT Id, Supervisor_User__c FROM Lead LIMIT 1];

            List<String> validSlots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
            String conflictSlot = validSlots.isEmpty() ? '2PM-3PM' : validSlots[0];
            Date conflictDate = Date.today().addDays(3);

            // Create a SECOND lead for the conflict via Utility
            TestDataUtility.AppointmentLeadParams conflictParams = new TestDataUtility.AppointmentLeadParams();
            conflictParams.supervisorId = existingLead.Supervisor_User__c;
            conflictParams.status = 'Approved';
            conflictParams.apptDate = conflictDate;
            conflictParams.slot = conflictSlot;

            TestDataUtility.createAppointmentLead(conflictParams);

            Test.startTest();
            try {
                // Try to schedule the first lead for the exact same time/date
                ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                    existingLead.Id,
                    existingLead.Supervisor_User__c,
                    String.valueOf(conflictDate),
                    conflictSlot,
                    'Virtual'
                );
                // If we reach this line, the exception was NOT thrown, which is a failure
                System.assert(false, 'Should have thrown exception due to slot conflict');
            } catch(AuraHandledException e) {
                // Success: The controller correctly threw the exception blocking the duplicate slot
                System.assert(true, 'Expected AuraHandledException was thrown');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testInputValidationMissingFields() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Lead testLead = [SELECT Id, Supervisor_User__c FROM Lead LIMIT 1];

            List<String> validSlots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
            String validSlot = validSlots.isEmpty() ? '9AM-10AM' : validSlots[0];

            Test.startTest();
            // 1. Missing Date
            try {
                ScheduleAppointmentController.scheduleAppointmentAndSendEmails(testLead.Id, testLead.Supervisor_User__c, null, validSlot, 'Type');
                System.assert(false, 'Should fail missing date');
            } catch(AuraHandledException e) {
                System.assert(true, 'Expected AuraHandledException for missing date');
            }

            // 2. Missing Slot
            try {
                ScheduleAppointmentController.scheduleAppointmentAndSendEmails(testLead.Id, testLead.Supervisor_User__c, '2025-01-01', null, 'Type');
                System.assert(false, 'Should fail missing slot');
            } catch(AuraHandledException e) {
                System.assert(true, 'Expected AuraHandledException for missing slot');
            }

            // 3. Missing Type
            try {
                ScheduleAppointmentController.scheduleAppointmentAndSendEmails(testLead.Id, testLead.Supervisor_User__c, '2025-01-01', validSlot, null);
                System.assert(false, 'Should fail missing type');
            } catch(AuraHandledException e) {
                System.assert(true, 'Expected AuraHandledException for missing type');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testInputValidationPastDate() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Lead testLead = [SELECT Id, Supervisor_User__c FROM Lead LIMIT 1];
            String pastDate = String.valueOf(Date.today().addDays(-1));

            List<String> validSlots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
            String validSlot = validSlots.isEmpty() ? '9AM-10AM' : validSlots[0];

            Test.startTest();
            try {
                ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                    testLead.Id, testLead.Supervisor_User__c, pastDate, validSlot, 'In Person'
                );
                System.assert(false, 'Should fail on past date');
            } catch(AuraHandledException e) {
                System.assert(true, 'Expected AuraHandledException for past date');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testInputValidationSameDayPastTime() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Lead testLead = [SELECT Id, Supervisor_User__c FROM Lead LIMIT 1];
            String todayDate = String.valueOf(Date.today());

            // "12AM" is 00:00. This is always in the past relative to "now" (unless running at exact midnight)
            String pastSlot = '12AM-1AM';

            Test.startTest();
            try {
                ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                    testLead.Id, testLead.Supervisor_User__c, todayDate, pastSlot, 'In Person'
                );
                System.assert(false, 'Should fail because 12AM today has already passed');
            } catch(AuraHandledException e) {
                System.assert(true, 'Expected exception for passed time slot');
            } catch(Exception e) {
                 System.assert(true, 'Caught exception: ' + e.getMessage());
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testDataValidationMissingSupervisor() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<String> validSlots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
            String validSlot = validSlots.isEmpty() ? '9AM-10AM' : validSlots[0];

            // Create a lead WITHOUT a supervisor using Utility (pass null ID)
            TestDataUtility.AppointmentLeadParams orphanParams = new TestDataUtility.AppointmentLeadParams();
            orphanParams.supervisorId = null;
            orphanParams.status = 'Pending';
            orphanParams.apptDate = null;
            orphanParams.slot = null;

            Lead orphanedLead = TestDataUtility.createAppointmentLead(orphanParams);

            Test.startTest();
            try {
                ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                    orphanedLead.Id, null, String.valueOf(Date.today().addDays(2)), validSlot, 'Type'
                );
                System.assert(false, 'Should fail due to missing supervisor');
            } catch(AuraHandledException e) {
                System.assert(true, 'Expected exception due to missing supervisor');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testDataValidationMissingLeadEmail() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Lead testLead = [SELECT Id, Supervisor_User__c, Email FROM Lead LIMIT 1];
            testLead.Email = null;
            update testLead;

            List<String> validSlots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
            String validSlot = validSlots.isEmpty() ? '9AM-10AM' : validSlots[0];
            String futureDate = String.valueOf(Date.today().addDays(2));

            Test.startTest();
            try {
                ScheduleAppointmentController.scheduleAppointmentAndSendEmails(
                    testLead.Id, testLead.Supervisor_User__c, futureDate, validSlot, 'Type'
                );
                System.assert(false, 'Should fail due to missing Lead Email');
            } catch(AuraHandledException e) {
                System.assert(true, 'Expected exception due to missing Lead Email');
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testPicklistHelpers() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Test.startTest();
            List<String> slots = ScheduleAppointmentController.getTimeSlotsPicklistValues();
            List<String> types = ScheduleAppointmentController.getAppointmentTypesPicklistValues();
            Test.stopTest();

            System.assertNotEquals(null, slots, 'Time Slots should return a list');
            System.assertNotEquals(null, types, 'Appointment Types should return a list');
        }
    }
}