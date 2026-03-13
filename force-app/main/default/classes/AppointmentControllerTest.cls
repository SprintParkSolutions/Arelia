@isTest
public class AppointmentControllerTest {

    @testSetup
    static void setup() {
        // 1. Create Supervisor
        User u = TestDataUtility.createSupervisorUser('apptSup');

        // 2. Create Email Templates
        System.runAs(new User(Id = UserInfo.getUserId())) {
            EmailTemplate t1 = new EmailTemplate(
                DeveloperName = 'Test_Appt_Approved',
                Name = 'Test Appt Approved',
                Subject = 'Approved',
                HtmlValue = '<html>Approved</html>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId()
            );
            
            EmailTemplate t2 = new EmailTemplate(
                DeveloperName = 'Test_Appt_Rescheduled',
                Name = 'Test Appt Rescheduled',
                Subject = 'Rescheduled',
                HtmlValue = '<html>Rescheduled</html>',
                TemplateType = 'custom',
                FolderId = UserInfo.getUserId()
            );
            insert new List<EmailTemplate>{t1, t2};
        }
    }

    // ==========================================
    // AVAILABILITY LOGIC TESTS
    // ==========================================

    @isTest
    static void testGetAvailableTimeSlotsNoConflicts() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'apptSup' LIMIT 1];
        Date testDate = Date.today().addDays(5);
        
        // Manual instantiation to avoid "ExcessiveParameterList" helper methods
        TestDataUtility.AppointmentLeadParams params = new TestDataUtility.AppointmentLeadParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Pending';
        params.apptDate = testDate;
        params.slot = null;
        
        Lead myLead = TestDataUtility.createAppointmentLead(params);

        Test.startTest();
        List<String> slots = AppointmentController.getAvailableTimeSlots(testDate, myLead.Id);
        Test.stopTest();

        Assert.isNotNull(slots, 'Should return slots list');
        Assert.isFalse(slots.isEmpty(), 'Should have slots available');
    }

    @isTest
    static void testGetAvailableTimeSlotsConflictApproved() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'apptSup' LIMIT 1];
        Date testDate = Date.today().addDays(5);
        String blockedSlot = '10AM-11AM';

        // 1. Create a "Blocker" Lead
        TestDataUtility.AppointmentLeadParams blockerParams = new TestDataUtility.AppointmentLeadParams();
        blockerParams.supervisorId = supervisor.Id;
        blockerParams.status = 'Approved';
        blockerParams.apptDate = testDate;
        blockerParams.slot = blockedSlot;
        TestDataUtility.createAppointmentLead(blockerParams);

        // 2. Create "My" Lead
        TestDataUtility.AppointmentLeadParams myParams = new TestDataUtility.AppointmentLeadParams();
        myParams.supervisorId = supervisor.Id;
        myParams.status = 'Pending';
        myParams.apptDate = testDate;
        Lead myLead = TestDataUtility.createAppointmentLead(myParams);

        Test.startTest();
        List<String> slots = AppointmentController.getAvailableTimeSlots(testDate, myLead.Id);
        Test.stopTest();

        Assert.isFalse(slots.contains(blockedSlot), 'Slot 10AM-11AM should be blocked by Approved lead');
    }

    @isTest
    static void testGetAvailableTimeSlotsConflictRescheduled() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'apptSup' LIMIT 1];
        Date testDate = Date.today().addDays(5);
        String blockedSlot = '11AM-12PM';

        // 1. Create a "Blocker" Lead
        TestDataUtility.AppointmentLeadParams blockerParams = new TestDataUtility.AppointmentLeadParams();
        blockerParams.supervisorId = supervisor.Id;
        blockerParams.status = 'Rescheduled';
        blockerParams.apptDate = Date.today(); // Initial date
        blockerParams.slot = '9AM-10AM';
        Lead blocker = TestDataUtility.createAppointmentLead(blockerParams);
        
        // Update to simulate reschedule fields
        blocker.Appointment_Rescheduled_Time__c = testDate;
        blocker.Time_Slots__c = blockedSlot;
        update blocker;

        // 2. Create "My" Lead
        TestDataUtility.AppointmentLeadParams myParams = new TestDataUtility.AppointmentLeadParams();
        myParams.supervisorId = supervisor.Id;
        myParams.status = 'Pending';
        myParams.apptDate = testDate;
        Lead myLead = TestDataUtility.createAppointmentLead(myParams);

        Test.startTest();
        List<String> slots = AppointmentController.getAvailableTimeSlots(testDate, myLead.Id);
        Test.stopTest();

        Assert.isFalse(slots.contains(blockedSlot), 'Slot 11AM-12PM should be blocked by Rescheduled lead');
    }

    @isTest
    static void testGetPicklistValues() {
        Test.startTest();
        List<String> values = AppointmentController.getTimeSlotsPicklistValues();
        Test.stopTest();
        Assert.isNotNull(values, 'Should return picklist values');
    }

    // ==========================================
    // STATUS UPDATE TESTS
    // ==========================================

    @isTest
    static void testUpdateStatusToApproved() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'apptSup' LIMIT 1];
        Date testDate = Date.today().addDays(5);
        
        TestDataUtility.AppointmentLeadParams params = new TestDataUtility.AppointmentLeadParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Pending';
        params.apptDate = testDate;
        params.slot = '10AM-11AM';
        Lead myLead = TestDataUtility.createAppointmentLead(params);

        Test.startTest();
        AppointmentController.updateAppointmentStatus(
            myLead.Id, 
            'Approved', 
            null, 
            null, 
            null
        );
        Test.stopTest();

        Lead updated = [SELECT Appointment_Status__c, Appointment_Completed__c FROM Lead WHERE Id = :myLead.Id];
        Assert.areEqual('Approved', updated.Appointment_Status__c, 'Status should be Approved');
        Assert.isTrue(updated.Appointment_Completed__c, 'Should be marked completed');
    }

    @isTest
    static void testUpdateStatusToRescheduled() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'apptSup' LIMIT 1];
        Date originalDate = Date.today().addDays(2);
        Date newDate = Date.today().addDays(5);
        String newSlot = '2PM-3PM';

        TestDataUtility.AppointmentLeadParams params = new TestDataUtility.AppointmentLeadParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Pending';
        params.apptDate = originalDate;
        params.slot = '10AM-11AM';
        Lead myLead = TestDataUtility.createAppointmentLead(params);

        Test.startTest();
        AppointmentController.updateAppointmentStatus(
            myLead.Id, 
            'Rescheduled', 
            'Busy', 
            newDate, 
            newSlot
        );
        Test.stopTest();

        Lead updated = [SELECT Appointment_Status__c, Appointment_Rescheduled_Time__c, Time_Slots__c FROM Lead WHERE Id = :myLead.Id];
        Assert.areEqual('Rescheduled', updated.Appointment_Status__c, 'Status should be Rescheduled');
        Assert.areEqual(newDate, updated.Appointment_Rescheduled_Time__c, 'Reschedule date should be saved');
        Assert.areEqual(newSlot, updated.Time_Slots__c, 'Reschedule slot should be saved');
    }

    @isTest
    static void testUpdateStatusRescheduleConflict() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'apptSup' LIMIT 1];
        Date targetDate = Date.today().addDays(5);
        String targetSlot = '10AM-11AM';

        // 1. Create Blocker
        TestDataUtility.AppointmentLeadParams blockerParams = new TestDataUtility.AppointmentLeadParams();
        blockerParams.supervisorId = supervisor.Id;
        blockerParams.status = 'Approved';
        blockerParams.apptDate = targetDate;
        blockerParams.slot = targetSlot;
        TestDataUtility.createAppointmentLead(blockerParams);

        // 2. Create My Lead
        TestDataUtility.AppointmentLeadParams myParams = new TestDataUtility.AppointmentLeadParams();
        myParams.supervisorId = supervisor.Id;
        myParams.status = 'Pending';
        myParams.apptDate = Date.today();
        myParams.slot = '9AM-10AM';
        Lead myLead = TestDataUtility.createAppointmentLead(myParams);

        Test.startTest();
        try {
            AppointmentController.updateAppointmentStatus(
                myLead.Id, 
                'Rescheduled', 
                'Conflict', 
                targetDate, 
                targetSlot
            );
            Assert.fail('Should throw exception for booking conflict');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should be thrown for booking conflict');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateStatusGuardClause() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'apptSup' LIMIT 1];
        
        // Create Lead that is ALREADY Approved
        TestDataUtility.AppointmentLeadParams params = new TestDataUtility.AppointmentLeadParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Approved';
        params.apptDate = Date.today();
        params.slot = '10AM-11AM';
        Lead myLead = TestDataUtility.createAppointmentLead(params);

        Test.startTest();
        try {
            AppointmentController.updateAppointmentStatus(
                myLead.Id, 
                'Approved', 
                null, 
                null, 
                null
            );
            Assert.fail('Should prevent updates to already approved records');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should be thrown for status lock');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateStatusValidationMissingFields() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'apptSup' LIMIT 1];
        
        TestDataUtility.AppointmentLeadParams params = new TestDataUtility.AppointmentLeadParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Pending';
        params.apptDate = Date.today();
        params.slot = '10AM-11AM';
        Lead myLead = TestDataUtility.createAppointmentLead(params);

        Test.startTest();
        try {
            // Missing Reschedule Date/Slot
            AppointmentController.updateAppointmentStatus(
                myLead.Id, 
                'Rescheduled', 
                null, 
                null, 
                null 
            );
            Assert.fail('Should validate missing fields');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'Exception should be thrown for missing fields');
        }
        Test.stopTest();
    }

    @isTest
    static void testUpdateStatusUnsupportedStatus() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'apptSup' LIMIT 1];
        
        TestDataUtility.AppointmentLeadParams params = new TestDataUtility.AppointmentLeadParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Pending';
        params.apptDate = Date.today();
        params.slot = '10AM-11AM';
        Lead myLead = TestDataUtility.createAppointmentLead(params);

        Test.startTest();
        try {
            AppointmentController.updateAppointmentStatus(
                myLead.Id, 
                'UnknownStatus', 
                null, 
                null, 
                null 
            );
            Assert.fail('Should validate status');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e, 'An exception should be thrown for unsupported status');
        }
        Test.stopTest();
    }
}