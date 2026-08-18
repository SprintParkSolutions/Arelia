public with sharing class PaymentTermReminderEmailSender {
    public class Request {
        @InvocableVariable(label='Payment Term Id' description='Payment Term record Id')
        public Id paymentTermId;
    }

    @InvocableMethod(label='Send Payment Term Reminder Email' description='Send a payment reminder email using the appropriate Email Template based on due date.')
    public static void sendReminderEmails(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> termIds = new Set<Id>();
        for (Request req : requests) {
            if (req != null && req.paymentTermId != null) {
                termIds.add(req.paymentTermId);
            }
        }
        if (termIds.isEmpty()) {
            return;
        }

        Map<String, Id> templateIds = fetchTemplateIds();
        if (templateIds.isEmpty()) {
            return;
        }

        List<Payment_Term__c> paymentTerms = [
            SELECT Id, Due_Date__c, Payment_Received__c, Project__c, Project__r.Name, Project__r.Client__c, Project__r.Client__r.Email
            FROM Payment_Term__c
            WHERE Id IN :termIds
        ];

        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (Payment_Term__c term : paymentTerms) {
            if (term.Payment_Received__c == true || term.Due_Date__c == null || term.Project__r == null || term.Project__r.Client__c == null) {
                continue;
            }

            Integer daysUntilDue = Date.today().daysBetween(term.Due_Date__c);
            String templateName;
            if (daysUntilDue == 3 || daysUntilDue == 0) {
                templateName = 'Arelia_Payment_Reminder';
            } else if (daysUntilDue == -1 || daysUntilDue == -3 || daysUntilDue == -7) {
                templateName = 'Arelia_Payment_Overdue';
            } else {
                continue;
            }

            Id emailTemplateId = templateIds.get(templateName);
            if (emailTemplateId == null) {
                continue;
            }

            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTemplateId(emailTemplateId);
            mail.setWhatId(term.Id);
            mail.setTargetObjectId(term.Project__r.Client__c);
            mail.setTreatTargetObjectAsRecipient(true);
            AreliaUtility.setOrgWideEmailAddress(mail, 'nareshp@sprintpark.com');
            mail.setSaveAsActivity(true);
            messages.add(mail);
        }

        if (!messages.isEmpty()) {
            Messaging.sendEmail(messages, false);
        }
    }

    private static Map<String, Id> fetchTemplateIds() {
        Map<String, Id> ids = new Map<String, Id>();
        for (EmailTemplate template : [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName IN ('Arelia_Payment_Reminder', 'Arelia_Payment_Overdue')
        ]) {
            ids.put(template.DeveloperName, template.Id);
        }
        return ids;
    }

    private static Id fetchOrgWideEmailAddressId(String address) {
        List<OrgWideEmailAddress> oweas = [
            SELECT Id
            FROM OrgWideEmailAddress
            WHERE Address = :address
            LIMIT 1
        ];
        return oweas.isEmpty() ? null : oweas[0].Id;
    }
}