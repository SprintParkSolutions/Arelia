/**
 * @name        LeadAppointmentEmailService
 * @description Builds and sends appointment emails to customer and supervisor.
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public with sharing class LeadAppointmentEmailService {

    public static void sendAppointmentEmails(List<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) {
            return;
        }

        List<Lead> leads = [SELECT Id,FirstName,LastName,Email,
                    Appointment_Date__c,Appointment_Time_Slots__c,
                    Appointment_Confirmation_Type__c,Appointment_Sent_date__c,
                    Supervisor_User__c,Supervisor_User__r.Name,
                    Supervisor_User__r.Email,Supervisor_User__r.Phone
                FROM Lead WHERE Id IN :leadIds];

        if (leads.isEmpty()) {
            return;
        }

        EmailTemplate leadTemplate = fetchTemplate(Label.Arelia_Living_Lead_Site_Visiting_Email_Template);
        EmailTemplate supervisorTemplate = fetchTemplate(Label.Arelia_Living_Supervisor_Site_Visiting_Email_Template);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Lead> leadsToStamp = new List<Lead>();

        for (Lead leadRec : leads) {
            if (String.isBlank(leadRec.Email)) {
                continue;
            }
            if (leadRec.Supervisor_User__r == null ||
                String.isBlank(leadRec.Supervisor_User__r.Email) ||
                String.isBlank(leadRec.Supervisor_User__r.Phone)) {
                continue;
            }
            if (leadRec.Appointment_Date__c == null ||
                String.isBlank(leadRec.Appointment_Time_Slots__c) ||
                String.isBlank(leadRec.Appointment_Confirmation_Type__c)) {
                continue;
            }

            String formattedDate = leadRec.Appointment_Date__c.format();
            String slot = leadRec.Appointment_Time_Slots__c;
            String appointmentType = leadRec.Appointment_Confirmation_Type__c;

            emails.add(prepareLeadEmail(leadRec,leadTemplate,formattedDate,
                    slot, appointmentType));

            emails.add(prepareSupervisorEmail(leadRec,supervisorTemplate,
                    formattedDate,slot,appointmentType));

            leadsToStamp.add(new Lead(Id = leadRec.Id,
                Appointment_Sent_date__c = Date.today()
            ));
        }

        if (!emails.isEmpty()) {
            Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);
            handleEmailResults(results);
        }

        if (!leadsToStamp.isEmpty()) {
            update leadsToStamp;
        }
    }

    private static EmailTemplate fetchTemplate(String developerName) {
        List<EmailTemplate> templates = [SELECT Id, HtmlValue, Subject
            FROM EmailTemplate WHERE DeveloperName = :developerName LIMIT 1];
        return templates.isEmpty() ? null : templates[0];
    }

    private static Messaging.SingleEmailMessage prepareLeadEmail(
        Lead leadRec, EmailTemplate template, String formattedDate,
        String timeSlot, String appointmentType)
    {
        String leadName = buildLeadName(leadRec);
        String approvalLink = Label.Arelia_Site_Label + Label.Site_Appointment_Link_Page + '?id=' + leadRec.Id;

        String htmlBody = template.HtmlValue
            .replace('{{{Recipient.Name}}}', leadName)
            .replace('{{{Supervisor_User__c.Name}}}', leadRec.Supervisor_User__r.Name)
            .replace('{{{Supervisor_User__c.Phone}}}', leadRec.Supervisor_User__r.Phone)
            .replace('{{{Supervisor_User__c.Email}}}', leadRec.Supervisor_User__r.Email)
            .replace('{{{appointmentDate}}}', formattedDate)
            .replace('{{{timeSlot}}}', timeSlot)
            .replace('{{{appointmentType}}}', appointmentType)
            .replace('{{{appointmentApprovalLink}}}', approvalLink);

        String subject = template.Subject
            .replace('{{{appointmentDate}}}', formattedDate)
            .replace('{{{timeSlot}}}', timeSlot)
            .replace('{{{appointmentType}}}', appointmentType)
            .replace('{{{leadName}}}', leadName);

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setTargetObjectId(leadRec.Id);
        email.setTreatTargetObjectAsRecipient(true);
        email.setSaveAsActivity(true);
        email.setSubject(subject);
        email.setHtmlBody(htmlBody);

        Id oweaId = getDefaultOrgWideEmailAddressId();
        if (oweaId != null) {
            email.setOrgWideEmailAddressId(oweaId);
        }

        return email;
    }

    private static Messaging.SingleEmailMessage prepareSupervisorEmail(
        Lead leadRec,EmailTemplate template,String formattedDate,
        String timeSlot,String appointmentType)
    {
        String leadName = buildLeadName(leadRec);

        String htmlBody = template.HtmlValue
            .replace('{{{Recipient.Name}}}', leadRec.Supervisor_User__r.Name)
            .replace('{{{leadName}}}', leadName)
            .replace('{{{leadEmail}}}', leadRec.Email)
            .replace('{{{appointmentDate}}}', formattedDate)
            .replace('{{{timeSlot}}}', timeSlot)
            .replace('{{{appointmentType}}}', appointmentType);

        String subject = template.Subject
            .replace('{{{appointmentDate}}}', formattedDate)
            .replace('{{{timeSlot}}}', timeSlot)
            .replace('{{{appointmentType}}}', appointmentType)
            .replace('{{{leadName}}}', leadName);

        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new String[] { leadRec.Supervisor_User__r.Email });
        email.setTargetObjectId(leadRec.Id);
        email.setTreatTargetObjectAsRecipient(false);
        email.setSaveAsActivity(true);
        email.setSubject(subject);
        email.setHtmlBody(htmlBody);

        Id oweaId = getDefaultOrgWideEmailAddressId();
        if (oweaId != null) {
            email.setOrgWideEmailAddressId(oweaId);
        }

        return email;
    }

    private static String buildLeadName(Lead leadRec) {
        String firstName = leadRec.FirstName == null ? '' : leadRec.FirstName;
        String lastName = leadRec.LastName == null ? '' : leadRec.LastName;
        return (firstName + ' ' + lastName).trim();
    }

    private static void handleEmailResults(Messaging.SendEmailResult[] results) {
        for (Messaging.SendEmailResult res : results) {
            if (!res.isSuccess()) {
                Messaging.SendEmailError[] errors = res.getErrors();
                if (errors != null && !errors.isEmpty()) {
                    throw new AuraHandledException('Appointment email failed: ' + errors[0].getMessage());
                }
            }
        }
    }

    private static Id getDefaultOrgWideEmailAddressId() {
        List<OrgWideEmailAddress> oweaList = [SELECT Id
            FROM OrgWideEmailAddress WHERE Address = :Label.Arelia_OWD LIMIT 1];
        return oweaList.isEmpty() ? null : oweaList[0].Id;
    }
}