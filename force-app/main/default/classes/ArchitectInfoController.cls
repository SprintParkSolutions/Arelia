/**
 * @description       : 
 * @author            : Arelia Space
 * @group             : 
 * @last modified on  : 05-11-2026
**/
public with sharing class ArchitectInfoController {

    private static final String ARELIA_OPPORTUNITY_RECORD_TYPE_NAME = 'Arelia';
    private static Id cachedAreliaOpportunityRecordTypeId;
    
    @AuraEnabled
    public static void updateAndSendEmail(Id recordId, String architectName, String architectEmail, String architectPhone) {
        // Best Practice 1: Server-Side Input Validation
        if (String.isBlank(recordId) || String.isBlank(architectEmail)) {
            throw new AuraHandledException('Required parameters are missing. Opportunity Id and Architect Email are required.');
        }

        // Best Practice 2: Transaction Control (All-or-Nothing)
        // If the email fails to send, we do not want the Opportunity record to save the new architect details.
        Savepoint sp = Database.setSavepoint();

        try {
            Opportunity existingOpportunity = [
                SELECT Id, RecordTypeId
                FROM Opportunity
                WHERE Id = :recordId
                LIMIT 1
            ];

            if (!isAreliaOpportunity(existingOpportunity)) {
                throw new AuraHandledException(
                    'Architect email is supported only for Arelia opportunities.'
                );
            }

            // 1. Update the Opportunity Record (Enforcing FLS with 'as user')
            Opportunity oppToUpdate = new Opportunity(
                Id = recordId,
                Architect_Name__c = architectName,
                Architect_Email__c = architectEmail,
                Architect_Contact__c = architectPhone
            );
            update as user oppToUpdate;
            
            // 2. Fetch the Org-Wide Email Address using the Custom Label
            List<OrgWideEmailAddress> owdAddresses = [
                SELECT Id 
                FROM OrgWideEmailAddress 
                WHERE Address = :System.Label.Arelia_OWD 
                LIMIT 1
            ];
            
            // 3. Fetch the specific Email Template
            List<EmailTemplate> templates = [
                SELECT Id 
                FROM EmailTemplate 
                WHERE DeveloperName = 'Architect_Opportunity_Mail' 
                LIMIT 1
            ];
            
            if (templates.isEmpty()) {
                throw new AuraHandledException('The email template Architect_Opportunity_Mail could not be found.');
            }
            
            // 4. Render the Email Template in memory
            Messaging.SingleEmailMessage renderedMail = Messaging.renderStoredEmailTemplate(
                templates[0].Id, 
                null, 
                recordId
            );
            
            // 5. Construct the actual email payload
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[] { architectEmail });
            mail.setSubject(renderedMail.getSubject());
            mail.setHtmlBody(renderedMail.getHtmlBody());
            mail.setPlainTextBody(renderedMail.getPlainTextBody());
            
            // Best Practice 3: Explicitly disable Activity saving 
            // (Since we aren't using a standard WhoId, leaving this true can sometimes throw an error)
            mail.setSaveAsActivity(false); 
            
            if (!owdAddresses.isEmpty()) {
                mail.setOrgWideEmailAddressId(owdAddresses[0].Id);
            }
            
            // 6. Send the compiled Email
            Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            
            // Best Practice 4: Explicitly check the SendEmailResult
            if (!results[0].isSuccess()) {
                throw new CalloutException(results[0].getErrors()[0].getMessage());
            }
            
        } catch (Exception e) {
            // Rollback the database if ANYTHING fails (DML, limits, or email dispatch)
            Database.rollback(sp);
            
            // Best Practice 5: Prevent LWC from swallowing the error message
            // Standard AuraHandledException sometimes masks the underlying error string on the frontend. 
            // Setting it explicitly ensures your Toast shows the real issue.
            AuraHandledException auraException = new AuraHandledException(e.getMessage());
            auraException.setMessage(e.getMessage());
            throw auraException;
        }
    }

    private static Boolean isAreliaOpportunity(Opportunity opportunityRecord) {
        if (opportunityRecord == null || opportunityRecord.RecordTypeId == null) {
            return false;
        }

        Id areliaOpportunityRecordTypeId = getAreliaOpportunityRecordTypeId();
        return areliaOpportunityRecordTypeId != null
            && opportunityRecord.RecordTypeId == areliaOpportunityRecordTypeId;
    }

    private static Id getAreliaOpportunityRecordTypeId() {
        if (cachedAreliaOpportunityRecordTypeId != null) {
            return cachedAreliaOpportunityRecordTypeId;
        }

        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByName()
            .get(ARELIA_OPPORTUNITY_RECORD_TYPE_NAME);

        if (recordTypeInfo == null) {
            return null;
        }

        cachedAreliaOpportunityRecordTypeId = recordTypeInfo.getRecordTypeId();
        return cachedAreliaOpportunityRecordTypeId;
    }
}