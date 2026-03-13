/**
 * @description Test class for AppointmentControllerToOpp.
 * Resolves coverage issues for appointment approval and rescheduling logic.
 */
@isTest
private class AppointmentControllerToOppTest {

    @testSetup
    static void setup() {
        // 1. Create Supervisor
        User u = TestDataUtility.createSupervisorUser('oppSup');

        // 2. Create Contact with Email (Crucial for sendConfirmationEmail coverage)
        Contact con = TestDataUtility.createContact('Test Contact', 'test@example.com', 'password123');

        // 3. Create Email Templates (Matches Label/DeveloperName logic in Controller)
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Mocking content with merge fields to cover string replacement logic
            String body = 'Hello {{{Recipient.Name}}}, Phone: {{{Recipient.Phone}}}, ' +
                          'Supervisor: {{{Supervisor_User__c.Name}}}, Date: {{{Re_Visit_Appointment_Date__c}}}';

            TestDataUtility.createSpecificEmailTemplate(
                'Opportunity_Appointment_Approved_Email', 
                'Approve Template', 
                'Approved: {{{Recipient.Name}}}', 
                body
            );

            TestDataUtility.createSpecificEmailTemplate(
                'Opportunity_Appointment_Rescheduled_Email', 
                'Reschedule Template', 
                'Rescheduled: {{{Recipient.Name}}}', 
                body
            );
        }
    }

    @isTest
    static void testUpdateStatusApprovedSuccess() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'oppSup' LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        
        TestDataUtility.AppointmentOppParams params = new TestDataUtility.AppointmentOppParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Pending';
        params.apptDate = Date.today().addDays(1);
        params.slot = '10AM-11AM';
        params.contactId = con.Id;
        Opportunity opp = TestDataUtility.createAppointmentOpportunity(params);

        Test.startTest();
        // Step 1 above ensures Primary_Contact__r.Email is available here
        AppointmentControllerToOpp.updateAppointmentStatus(opp.Id, 'Approved', null, null, null);
        Test.stopTest();

        Opportunity updated = [SELECT Re_Visit_Site_Appointment_Status__c FROM Opportunity WHERE Id = :opp.Id];
        Assert.areEqual('Approved', updated.Re_Visit_Site_Appointment_Status__c, 'Status should be Approved');
    }

    @isTest
    static void testUpdateStatusRescheduledSuccess() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'oppSup' LIMIT 1];
        Contact con = [SELECT Id FROM Contact LIMIT 1];
        Date newDate = Date.today().addDays(7);
        String newSlot = '3PM-4PM';

        TestDataUtility.AppointmentOppParams params = new TestDataUtility.AppointmentOppParams();
        params.supervisorId = supervisor.Id;
        params.status = 'Pending';
        params.contactId = con.Id;
        Opportunity opp = TestDataUtility.createAppointmentOpportunity(params);

        Test.startTest();
        AppointmentControllerToOpp.updateAppointmentStatus(opp.Id, 'Rescheduled', 'Conflict', newDate, newSlot);
        Test.stopTest();

        Opportunity updated = [SELECT Re_Visit_Site_Appointment_Status__c, Re_Visit_Appointment_Rescheduled_Date__c 
                               FROM Opportunity WHERE Id = :opp.Id];
        Assert.areEqual('Rescheduled', updated.Re_Visit_Site_Appointment_Status__c, 'Status did not update to Rescheduled');
        Assert.areEqual(newDate, updated.Re_Visit_Appointment_Rescheduled_Date__c, 'Reschedule date mismatch');
    }

    @isTest
    static void testGetAvailableSlotsWithConflicts() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'oppSup' LIMIT 1];
        Date testDate = Date.today().addDays(3);
        String leadConflictSlot = '11AM-12PM';
        String oppConflictSlot = '4PM-5PM';

        // 1. Create Lead Blocker
        TestDataUtility.AppointmentLeadParams leadP = new TestDataUtility.AppointmentLeadParams();
        leadP.supervisorId = supervisor.Id;
        leadP.status = 'Approved';
        leadP.apptDate = testDate;
        leadP.slot = leadConflictSlot;
        TestDataUtility.createAppointmentLead(leadP);

        // 2. Create Opp Blocker
        TestDataUtility.AppointmentOppParams oppP = new TestDataUtility.AppointmentOppParams();
        oppP.supervisorId = supervisor.Id;
        oppP.status = 'Approved';
        oppP.apptDate = testDate;
        oppP.slot = oppConflictSlot;
        oppP.contactId = [SELECT Id FROM Contact LIMIT 1].Id;
        TestDataUtility.createAppointmentOpportunity(oppP);

        // 3. Create My Opportunity
        Opportunity myOpp = TestDataUtility.createOpportunity('Check Slots', supervisor.Id);

        Test.startTest();
        List<String> available = AppointmentControllerToOpp.getAvailableTimeSlots(testDate, myOpp.Id);
        List<String> picklist = AppointmentControllerToOpp.getTimeSlotsPicklistValues();
        Test.stopTest();

        Assert.isNotNull(available, 'Available slots list should not be null');
        Assert.isFalse(available.contains(leadConflictSlot), 'Slot blocked by Lead was returned');
        Assert.isFalse(available.contains(oppConflictSlot), 'Slot blocked by Opp was returned');
        Assert.isFalse(picklist.isEmpty(), 'Picklist values should not be empty');
    }

    @isTest
    static void testUpdateStatusExceptions() {
        User supervisor = [SELECT Id FROM User WHERE Alias = 'oppSup' LIMIT 1];
        Opportunity opp = TestDataUtility.createOpportunity('Exception Test', supervisor.Id);
        
        Test.startTest();
        // Test 1: Invalid Status
        Boolean caught = false;
        try {
            AppointmentControllerToOpp.updateAppointmentStatus(opp.Id, 'Invalid', null, null, null);
        } catch (AuraHandledException e) {
            caught = true;
        }
        Assert.isTrue(caught, 'Unsupported status should throw exception');

        // Test 2: Reschedule missing data
        caught = false;
        try {
            AppointmentControllerToOpp.updateAppointmentStatus(opp.Id, 'Rescheduled', null, null, null);
        } catch (AuraHandledException e) {
            caught = true;
        }
        Assert.isTrue(caught, 'Reschedule without date/slot should throw exception');
        
        // Test 3: Missing Opp ID
        caught = false;
        try {
            AppointmentControllerToOpp.updateAppointmentStatus(null, 'Approved', null, null, null);
        } catch (AuraHandledException e) {
            caught = true;
        }
        Assert.isTrue(caught, 'Missing Opportunity ID should throw exception');
        Test.stopTest();
    }
}