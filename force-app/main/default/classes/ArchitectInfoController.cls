/**
 * @description Handles architect detail updates and architect email delivery for Arelia Opportunity records.
 * @author Arelia Space
 * @last modified on 30-07-2026
 */
public with sharing class ArchitectInfoController {
    private static final String ARCHITECT_EMAIL_TEMPLATE_DEVELOPER_NAME = 'Architect_Opportunity_Mail';
    private static final String ERROR_MISSING_PARAMETERS =
        'Required parameters are missing. Opportunity Id and Architect Email are required.';
    private static final String ERROR_TEMPLATE_NOT_FOUND =
        'The email template Architect_Opportunity_Mail could not be found.';
    private static final String ERROR_UNSUPPORTED_RECORD_TYPE =
        'Architect email is supported only for Arelia opportunities.';
    @TestVisible
    private static String templateDeveloperName = ARCHITECT_EMAIL_TEMPLATE_DEVELOPER_NAME;

    /**
     * @description Updates architect fields on an Arelia Opportunity. The architect email itself is sent by
     * OpportunityTriggerHandler/sendArchitectEmails via the OpportunityAfterUpdate trigger, so it fires for
     * this update the same as it would for any other source.
     * @param recordId Opportunity Id.
     * @param architectName Architect name to save on the Opportunity.
     * @param architectEmail Architect email to save and send the email to.
     * @param architectPhone Architect phone number to save on the Opportunity.
     */
    @AuraEnabled
    @SuppressWarnings('PMD.ExcessiveParameterList')
    public static void updateAndSendEmail(
        Id recordId,
        String architectName,
        String architectEmail,
        String architectPhone
    ) {
        validateRequest(recordId, architectEmail);

        Savepoint savepointReference = Database.setSavepoint();

        try {
            validateAreliaOpportunity(recordId);
            updateOpportunityArchitectDetails(
                new Opportunity(
                    Id = recordId,
                    Architect_Name__c = architectName,
                    Architect_Email__c = architectEmail,
                    Architect_Contact__c = architectPhone
                )
            );
        } catch (Exception ex) {
            Database.rollback(savepointReference);
            throw buildAuraHandledException(ex.getMessage());
        }
    }

    /**
     * @description Sends the architect email for every qualifying Opportunity in a trigger context,
     * regardless of what updated the record (component, Data Loader, Flow, API, etc). An Opportunity
     * qualifies when it is an Arelia Opportunity, Architect_Name__c/Architect_Email__c/Architect_Contact__c
     * are all populated, and at least one of those three fields changed on this update. Meant to be called
     * from OpportunityTriggerHandler in an after update context. Failures are logged, not thrown, so an
     * email issue never rolls back the triggering Opportunity update.
     * @param newOpps Trigger.new Opportunity records.
     * @param oldMap Trigger.oldMap Opportunity records.
     */
    public static void sendArchitectEmails(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {
        List<Opportunity> qualifiedOpportunities = getOpportunitiesQualifiedForArchitectEmail(newOpps, oldMap);

        if (qualifiedOpportunities.isEmpty()) {
            return;
        }

        Id templateId = AreliaUtility.getEmailTemplateIdByDeveloperName(templateDeveloperName);

        if (templateId == null) {
            System.debug(LoggingLevel.ERROR, ERROR_TEMPLATE_NOT_FOUND);
            return;
        }

        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

        for (Opportunity opp : qualifiedOpportunities) {
            try {
                emailsToSend.add(buildArchitectEmail(templateId, opp.Id, opp.Architect_Email__c));
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Failed to build architect email for ' + opp.Id + ': ' + ex.getMessage());
            }
        }

        if (emailsToSend.isEmpty()) {
            return;
        }

        try {
            Messaging.sendEmail(emailsToSend);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Failed to send architect email(s): ' + ex.getMessage());
        }
    }

    private static List<Opportunity> getOpportunitiesQualifiedForArchitectEmail(
        List<Opportunity> newOpps,
        Map<Id, Opportunity> oldMap
    ) {
        List<Opportunity> qualifiedOpportunities = new List<Opportunity>();
        Id areliaOpportunityRecordTypeId = AreliaUtility.getAreliaOpportunityRecordTypeId();

        if (areliaOpportunityRecordTypeId == null) {
            return qualifiedOpportunities;
        }

        for (Opportunity newOpp : newOpps) {
            Opportunity oldOpp = oldMap == null ? null : oldMap.get(newOpp.Id);

            if (isQualifiedForArchitectEmail(newOpp, oldOpp, areliaOpportunityRecordTypeId)) {
                qualifiedOpportunities.add(newOpp);
            }
        }

        return qualifiedOpportunities;
    }

    private static Boolean isQualifiedForArchitectEmail(
        Opportunity newOpp,
        Opportunity oldOpp,
        Id areliaOpportunityRecordTypeId
    ) {
        Boolean isAreliaOpportunity = newOpp.RecordTypeId == areliaOpportunityRecordTypeId;
        Boolean fieldsPopulated = String.isNotBlank(newOpp.Architect_Name__c)
            && String.isNotBlank(newOpp.Architect_Email__c)
            && String.isNotBlank(newOpp.Architect_Contact__c);
        Boolean fieldsChanged = oldOpp == null
            || newOpp.Architect_Name__c != oldOpp.Architect_Name__c
            || newOpp.Architect_Email__c != oldOpp.Architect_Email__c
            || newOpp.Architect_Contact__c != oldOpp.Architect_Contact__c;

        return isAreliaOpportunity && fieldsPopulated && fieldsChanged;
    }

    private static void validateRequest(Id recordId, String architectEmail) {
        if (recordId == null || String.isBlank(architectEmail)) {
            throw buildAuraHandledException(ERROR_MISSING_PARAMETERS);
        }
    }

    private static void validateAreliaOpportunity(Id recordId) {
        Id areliaOpportunityRecordTypeId = AreliaUtility.getAreliaOpportunityRecordTypeId();

        if (
            areliaOpportunityRecordTypeId == null ||
            !hasAreliaOpportunity(recordId, areliaOpportunityRecordTypeId)
        ) {
            throw buildAuraHandledException(ERROR_UNSUPPORTED_RECORD_TYPE);
        }
    }

    private static Boolean hasAreliaOpportunity(Id recordId, Id areliaOpportunityRecordTypeId) {
        return ![SELECT Id FROM Opportunity WHERE Id = :recordId
        AND RecordTypeId = :areliaOpportunityRecordTypeId LIMIT 1]
        .isEmpty();
    }

    private static void updateOpportunityArchitectDetails(Opportunity oppToUpdate) {
        update as user oppToUpdate;
    }

    private static Messaging.SingleEmailMessage buildArchitectEmail(Id templateId, Id recordId, String architectEmail) {
        Messaging.SingleEmailMessage renderedMail = Messaging.renderStoredEmailTemplate(
            templateId,
            null,
            recordId
        );

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ architectEmail });
        mail.setSubject(renderedMail.getSubject());
        mail.setHtmlBody(renderedMail.getHtmlBody());
        mail.setPlainTextBody(renderedMail.getPlainTextBody());
        mail.setSaveAsActivity(false);
        AreliaUtility.setOrgWideEmailAddress(mail, System.Label.Arelia_OWD);
        return mail;
    }

    private static AuraHandledException buildAuraHandledException(String message) {
        AuraHandledException auraException = new AuraHandledException(message);
        auraException.setMessage(message);
        return auraException;
    }
}