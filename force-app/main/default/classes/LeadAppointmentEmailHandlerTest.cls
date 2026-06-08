@IsTest
@SuppressWarnings('PMD.CognitiveComplexity,PMD.MethodNamingConventions')
private class LeadAppointmentEmailHandlerTest {

    @TestSetup
    static void setupData() {
        User supervisor = TestDataUtility.createSupervisorUser('ApptSup');
        supervisor.Phone = '555-444-3333';
        update supervisor;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<EmailTemplate> templates = new List<EmailTemplate>();

            EmailTemplate t1 = new EmailTemplate();
            t1.DeveloperName = Label.Arelia_Living_Lead_Site_Visiting_Email_Template;
            t1.Name = 'Lead Appointment Template Handler';
            t1.Subject = 'Appointment {{{appointmentDate}}} {{{appointmentType}}}';
            t1.HtmlValue =
                'Hi {{{Recipient.Name}}} {{{appointmentDate}}} {{{timeSlot}}} {{{appointmentType}}} {{{appointmentApprovalLink}}}';
            t1.TemplateType = 'text';
            t1.FolderId = UserInfo.getUserId();
            templates.add(t1);

            EmailTemplate t2 = new EmailTemplate();
            t2.DeveloperName = Label.Arelia_Living_Supervisor_Site_Visiting_Email_Template;
            t2.Name = 'Supervisor Appointment Template Handler';
            t2.Subject = 'Supervisor {{{appointmentDate}}} {{{appointmentType}}}';
            t2.HtmlValue =
                'Hi {{{Recipient.Name}}} lead {{{leadName}}} {{{leadEmail}}} {{{appointmentDate}}} {{{timeSlot}}} {{{appointmentType}}}';
            t2.TemplateType = 'text';
            t2.FolderId = UserInfo.getUserId();
            templates.add(t2);

            insert templates;
        }
    }

    @IsTest
    static void testShouldSendAppointmentEmail_NewAppointment() {
        User supervisor = [SELECT Id FROM User WHERE Alias LIKE 'Appt%' LIMIT 1];

        Lead oldLead = new Lead(
            Id = '00Q000000000001AAA',
            Email = 'test1@example.com',
            Supervisor_User__c = supervisor.Id
        );

        Lead newLead = new Lead(
            Id = '00Q000000000001AAA',
            Email = 'test1@example.com',
            Supervisor_User__c = supervisor.Id,
            Appointment_Date__c = Date.today().addDays(2),
            Appointment_Time_Slots__c = '9AM-10AM',
            Appointment_Confirmation_Type__c = 'New'
        );

        Boolean result = LeadAppointmentEmailHandler.shouldSendAppointmentEmail(newLead, oldLead);
        System.assertEquals(true, result, 'New appointment should send email');
    }

    @IsTest
    static void testShouldSendAppointmentEmail_FollowupAppointment() {
        User supervisor = [SELECT Id FROM User WHERE Alias LIKE 'Appt%' LIMIT 1];

        Lead oldLead = new Lead(
            Id = '00Q000000000002AAA',
            Email = 'test2@example.com',
            Supervisor_User__c = supervisor.Id,
            Appointment_Date__c = Date.today().addDays(2),
            Appointment_Time_Slots__c = '9AM-10AM',
            Appointment_Confirmation_Type__c = 'New'
        );

        Lead newLead = new Lead(
            Id = '00Q000000000002AAA',
            Email = 'test2@example.com',
            Supervisor_User__c = supervisor.Id,
            Appointment_Date__c = Date.today().addDays(4),
            Appointment_Time_Slots__c = '10AM-11AM',
            Appointment_Confirmation_Type__c = 'Followup'
        );

        Boolean result = LeadAppointmentEmailHandler.shouldSendAppointmentEmail(newLead, oldLead);
        System.assertEquals(true, result, 'Followup appointment change should send email');
    }

    @IsTest
    static void testShouldNotSendWhenFieldsMissing() {
        User supervisor = [SELECT Id FROM User WHERE Alias LIKE 'Appt%' LIMIT 1];

        Lead oldLead = new Lead(
            Id = '00Q000000000003AAA',
            Email = 'test3@example.com',
            Supervisor_User__c = supervisor.Id
        );

        Lead newLead = new Lead(
            Id = '00Q000000000003AAA',
            Email = 'test3@example.com',
            Supervisor_User__c = supervisor.Id,
            Appointment_Date__c = Date.today().addDays(2)
        );

        Boolean result = LeadAppointmentEmailHandler.shouldSendAppointmentEmail(newLead, oldLead);
        System.assertEquals(false, result, 'Missing slot/type should not send email');
    }

    @IsTest
    static void testShouldNotSendWhenNothingChanged() {
        User supervisor = [SELECT Id FROM User WHERE Alias LIKE 'Appt%' LIMIT 1];

        Lead oldLead = new Lead(
            Id = '00Q000000000004AAA',
            Email = 'test4@example.com',
            Supervisor_User__c = supervisor.Id,
            Appointment_Date__c = Date.today().addDays(2),
            Appointment_Time_Slots__c = '9AM-10AM',
            Appointment_Confirmation_Type__c = 'New'
        );

        Lead newLead = new Lead(
            Id = '00Q000000000004AAA',
            Email = 'test4@example.com',
            Supervisor_User__c = supervisor.Id,
            Appointment_Date__c = oldLead.Appointment_Date__c,
            Appointment_Time_Slots__c = oldLead.Appointment_Time_Slots__c,
            Appointment_Confirmation_Type__c = oldLead.Appointment_Confirmation_Type__c
        );

        Boolean result = LeadAppointmentEmailHandler.shouldSendAppointmentEmail(newLead, oldLead);
        System.assertEquals(false, result, 'No change should not send email');
    }

    @IsTest
    static void testSendAppointmentEmailsOnUpdate() {
        User supervisor = [SELECT Id, Email, Phone FROM User WHERE Alias LIKE 'Appt%' LIMIT 1];

        Lead l = new Lead(
            FirstName = 'Handler',
            LastName = 'Lead',
            Company = 'Handler Co',
            Email = 'handler@test.com',
            Supervisor_User__c = supervisor.Id,
            Status = 'Open - Not Contacted'
        );
        insert l;

        update new Lead(
            Id = l.Id,
            Appointment_Date__c = Date.today().addDays(5),
            Appointment_Time_Slots__c = '9AM-10AM',
            Appointment_Confirmation_Type__c = 'Followup'
        );

        Lead refreshed = [
            SELECT Appointment_Sent_date__c,
                   Appointment_Date__c,
                   Appointment_Time_Slots__c,
                   Appointment_Confirmation_Type__c
            FROM Lead
            WHERE Id = :l.Id
        ];

        System.assertEquals(Date.today(), refreshed.Appointment_Sent_date__c, 'Sent date should be stamped');
        System.assertEquals('Followup', refreshed.Appointment_Confirmation_Type__c, 'Appointment type should be updated');
    }
}