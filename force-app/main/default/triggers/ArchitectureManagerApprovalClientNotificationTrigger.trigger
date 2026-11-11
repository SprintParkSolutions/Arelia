trigger ArchitectureManagerApprovalClientNotificationTrigger on Architecture_Design__c (after update) {

    // =====================================================
    // 1. EXISTING MOBILE PUSH NOTIFICATION
    // =====================================================

    Set<Id> designIdsToNotify = new Set<Id>();

    // Client and supervisor emails for Supervisor App approvals.
    Set<Id> designIdsForEmail = new Set<Id>();

    // Existing execution-context distinction.
    Boolean isNonSiteContext = Site.getSiteId() == null;

    for (Architecture_Design__c newDesign : Trigger.new) {

        Architecture_Design__c oldDesign = Trigger.oldMap.get(newDesign.Id);

        if (oldDesign == null) {
            continue;
        }

        // EXISTING CONDITIONS - UNCHANGED

        Boolean managerApprovalJustGiven = newDesign.Manager_Approval__c == true && oldDesign.Manager_Approval__c != true;
        Boolean approvedDateJustPopulated = newDesign.Architect_Approved_Date__c != null && oldDesign.Architect_Approved_Date__c == null;
        Boolean approvalReady = newDesign.Manager_Approval__c == true && newDesign.Architect_Approved_Date__c != null && newDesign.Opportunity__c != null;

        // Existing mobile push logic - unchanged.
        if (
            approvalReady &&
            (
                managerApprovalJustGiven ||
                approvedDateJustPopulated
            )
        ) {
            designIdsToNotify.add(newDesign.Id);
        }

        // =================================================
        // CLIENT + SUPERVISOR EMAIL NOTIFICATIONS
        // =================================================

        // Site approvals use ManagerApprovalController.
        // Non-Site approvals use this trigger.
        // Approval must change from false/null to true.

        if (managerApprovalJustGiven && newDesign.Opportunity__c != null && isNonSiteContext) {
            designIdsForEmail.add(newDesign.Id);
        }
    }

    // =====================================================
    // 2. EXISTING MOBILE PUSH JOB - UNCHANGED
    // =====================================================

    if (!designIdsToNotify.isEmpty()) {

        System.enqueueJob(
            new ArchitectureManagerApprovedClientPushJob(
                designIdsToNotify
            )
        );
    }

    // =====================================================
    // 3. CLIENT AND SUPERVISOR EMAIL NOTIFICATIONS
    // =====================================================

    if (!designIdsForEmail.isEmpty()) {

        try {

            // Existing email template custom labels.
            String clientTemplateName = System.Label.Client_Final_Response_Template;

            String supervisorTemplateName = System.Label.Manager_Response_Notification_Template;

            Set<String> templateNames = new Set<String>{
                clientTemplateName, supervisorTemplateName
            };

            Map<String, EmailTemplate> templatesByName = new Map<String, EmailTemplate>();

            for (EmailTemplate templateRecord : [
                SELECT Id, DeveloperName, Subject, HtmlValue
                FROM EmailTemplate
                WHERE DeveloperName IN :templateNames
            ]) {
                templatesByName.put(
                    templateRecord.DeveloperName,
                    templateRecord
                );
            }

            EmailTemplate clientTemplate = templatesByName.get(clientTemplateName);

            EmailTemplate supervisorTemplate = templatesByName.get(supervisorTemplateName);

            if (clientTemplate == null) {
                System.debug(
                    LoggingLevel.ERROR,
                    'ARCHITECTURE EMAIL: Client template not found.'
                );
            }

            if (supervisorTemplate == null) {
                System.debug(
                    LoggingLevel.ERROR,
                    'ARCHITECTURE EMAIL: Supervisor template not found.'
                );
            }

            // =================================================
            // 4. GET ARELIA OPPORTUNITY RECORD TYPE
            // =================================================

            Id areliaRecordTypeId = AreliaUtility.getAreliaOpportunityRecordTypeId();

            // =================================================
            // 5. FETCH APPROVED ARCHITECTURE DESIGNS
            // =================================================

            List<Architecture_Design__c> designs = [
                SELECT Id, Opportunity__c, Opportunity__r.RecordTypeId, Opportunity__r.Name,
                    Opportunity__r.Project_Description__c, Opportunity__r.Lead_Name__c, Opportunity__r.Supervisor_User_Email__c,
                    Opportunity__r.Primary_Contact__r.Email, Opportunity__r.Supervisor_User__r.FirstName, Opportunity__r.Supervisor_User__r.LastName,
                    Opportunity__r.Supervisor_User__r.Phone, Project__r.Name, Manager_Approval__c, Manager_Comments__c
                FROM Architecture_Design__c WHERE Id IN :designIdsForEmail AND Manager_Approval__c = true AND Opportunity__c != null
            ];

            // =================================================
            // 6. ORGANIZATION-WIDE EMAIL ADDRESS
            // =================================================

            Id orgWideEmailId;
            List<OrgWideEmailAddress> orgAddresses = [SELECT Id FROM OrgWideEmailAddress WHERE Address = :System.Label.Arelia_OWD LIMIT 1];

            if (!orgAddresses.isEmpty()) {
                orgWideEmailId = orgAddresses[0].Id;
            }

            // =================================================
            // 7. FETCH RELATED FILES
            // =================================================

            Map<Id, Set<Id>> documentsByDesign = new Map<Id, Set<Id>>();
            Set<Id> documentIds = new Set<Id>();
            for (ContentDocumentLink fileLink : [SELECT LinkedEntityId, ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :designIdsForEmail]) {

                if (!documentsByDesign.containsKey(fileLink.LinkedEntityId)) {
                    documentsByDesign.put(
                        fileLink.LinkedEntityId,
                        new Set<Id>()
                    );
                }

                documentsByDesign.get(fileLink.LinkedEntityId).add(fileLink.ContentDocumentId);
                documentIds.add(fileLink.ContentDocumentId);
            }

            Map<Id, ContentVersion> latestFiles =
                new Map<Id, ContentVersion>();

            if (!documentIds.isEmpty()) {

                for (ContentVersion fileVersion : [
                    SELECT
                        Id,
                        ContentDocumentId,
                        Title,
                        FileExtension,
                        VersionData
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :documentIds
                    AND IsLatest = true
                ]) {

                    latestFiles.put(
                        fileVersion.ContentDocumentId,
                        fileVersion
                    );
                }
            }

            // =================================================
            // 8. BUILD CLIENT AND SUPERVISOR EMAILS
            // =================================================

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            List<String> emailDescriptions = new List<String>();
            for (Architecture_Design__c design : designs) {

                // Preserve existing Arelia record type restriction.
                if (
                    areliaRecordTypeId == null ||
                    design.Opportunity__r == null ||
                    design.Opportunity__r.RecordTypeId !=
                        areliaRecordTypeId
                ) {
                    continue;
                }

                // =================================================
                // MERGE FIELD VALUES
                // =================================================

                String projectName =
                    design.Opportunity__r.Name == null
                    ? 'Unknown Project'
                    : design.Opportunity__r.Name;

                String projectDescription =
                    design.Opportunity__r.Project_Description__c == null
                    ? ''
                    : design.Opportunity__r.Project_Description__c;

                String clientName =
                    design.Opportunity__r.Lead_Name__c == null
                    ? 'Valued Client'
                    : design.Opportunity__r.Lead_Name__c;

                String supervisorEmail = design.Opportunity__r.Supervisor_User_Email__c == null ? '' : design.Opportunity__r.Supervisor_User_Email__c;
                String supervisorName = 'Enrollment Team';
                String supervisorPhone = '';

                if (design.Opportunity__r.Supervisor_User__r != null) {

                    User supervisor = design.Opportunity__r.Supervisor_User__r;
                    String firstName = supervisor.FirstName == null ? '' : supervisor.FirstName;
                    String lastName = supervisor.LastName == null  ? '' : supervisor.LastName;
                    supervisorName = (firstName + ' ' + lastName).trim();
                    supervisorPhone = supervisor.Phone == null ? '' : supervisor.Phone;
                }

                String comments =
                    String.isNotBlank(design.Manager_Comments__c)
                    ? design.Manager_Comments__c
                    : 'No comments provided.';

                Map<String, String> mergeFields =
                    new Map<String, String>{
                        '[PROJECT_NAME]' => projectName,
                        '[PROJECT_DESCRIPTION]' => projectDescription,
                        '[DECISION]' => 'Approved',
                        '[COMMENTS]' => comments,
                        '[SUPERVISOR_NAME]' => supervisorName,
                        '[SUPERVISOR_EMAIL]' => supervisorEmail,
                        '[SUPERVISOR_PHONE]' => supervisorPhone,
                        '[CLIENT_NAME]' => clientName
                    };

                // =================================================
                // BUILD FILE ATTACHMENTS
                // =================================================

                List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();

                if (documentsByDesign.containsKey(design.Id)) {

                    for (Id documentId :
                        documentsByDesign.get(design.Id)) {

                        if (!latestFiles.containsKey(documentId)) {
                            continue;
                        }

                        ContentVersion fileVersion = latestFiles.get(documentId);

                        Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();

                        attachment.setFileName(
                            fileVersion.Title +
                            (
                                String.isBlank(fileVersion.FileExtension)
                                ? ''
                                : '.' + fileVersion.FileExtension
                            )
                        );

                        attachment.setBody(fileVersion.VersionData);

                        attachments.add(attachment);
                    }
                }

                // =================================================
                // CLIENT EMAIL - EXISTING FUNCTIONALITY
                // =================================================

                String clientEmail = '';

                if (design.Opportunity__r.Primary_Contact__r != null) {
                    clientEmail = design.Opportunity__r.Primary_Contact__r.Email;
                }

                if (clientTemplate != null && String.isNotBlank(clientTemplate.HtmlValue) && String.isNotBlank(clientEmail)) {
                    String clientSubject = clientTemplate.Subject == null ? '' : clientTemplate.Subject;
                    String clientBody = clientTemplate.HtmlValue;
                    for (String mergeKey : mergeFields.keySet()) {
                        clientSubject = clientSubject.replace(mergeKey, mergeFields.get(mergeKey));
                        clientBody = clientBody.replace(mergeKey, mergeFields.get(mergeKey));
                    }

                    Messaging.SingleEmailMessage clientMail = new Messaging.SingleEmailMessage();
                    clientMail.setToAddresses(new List<String>{ clientEmail });
                    clientMail.setSubject(clientSubject);
                    clientMail.setHtmlBody(clientBody);

                    if (orgWideEmailId != null) {
                        clientMail.setOrgWideEmailAddressId(
                            orgWideEmailId
                        );
                    }

                    if (!attachments.isEmpty()) {
                        clientMail.setFileAttachments(attachments);
                    }

                    emails.add(clientMail);
                    emailDescriptions.add( 'CLIENT | Design: ' + design.Id + ' | Recipient: ' + clientEmail);
                }

                // =================================================
                // NEW: SUPERVISOR EMAIL NOTIFICATION
                // =================================================

                if (supervisorTemplate != null && String.isNotBlank(supervisorTemplate.HtmlValue) && String.isNotBlank(supervisorEmail)) {

                    String supervisorSubject =
                        supervisorTemplate.Subject == null
                        ? ''
                        : supervisorTemplate.Subject;

                    String supervisorBody = supervisorTemplate.HtmlValue;

                    // Apply same merge fields as existing controller.
                    for (String mergeKey : mergeFields.keySet()) {

                        supervisorSubject = supervisorSubject.replace(mergeKey, mergeFields.get(mergeKey));
                        supervisorBody = supervisorBody.replace(mergeKey, mergeFields.get(mergeKey));
                    }

                    Messaging.SingleEmailMessage supervisorMail = new Messaging.SingleEmailMessage();

                    supervisorMail.setToAddresses(
                        new List<String>{ supervisorEmail }
                    );

                    supervisorMail.setSubject(supervisorSubject);
                    supervisorMail.setHtmlBody(supervisorBody);

                    if (orgWideEmailId != null) {
                        supervisorMail.setOrgWideEmailAddressId(
                            orgWideEmailId
                        );
                    }

                    // Same Salesforce attachments.
                    if (!attachments.isEmpty()) {
                        supervisorMail.setFileAttachments(attachments);
                    }

                    emails.add(supervisorMail);

                    emailDescriptions.add(
                        'SUPERVISOR | Design: ' + design.Id +
                        ' | Recipient: ' + supervisorEmail
                    );
                }
            }

            // =====================================================
            // 9. SEND EMAILS
            // =====================================================

            if (!emails.isEmpty()) {

                Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);

                for (
                    Integer index = 0;
                    index < results.size();
                    index++
                ) {

                    if (results[index].isSuccess()) {

                        System.debug(
                            LoggingLevel.INFO,
                            'ARCHITECTURE EMAIL ACCEPTED: ' +
                            emailDescriptions[index]
                        );

                    } else {

                        for (Messaging.SendEmailError emailError : results[index].getErrors()) {

                            System.debug(
                                LoggingLevel.ERROR,
                                'ARCHITECTURE EMAIL FAILED: ' +
                                emailDescriptions[index] +
                                ' | Error: ' +
                                emailError.getMessage()
                            );
                        }
                    }
                }
            }

        } catch (Exception emailException) {

            System.debug(
                LoggingLevel.ERROR,
                'ARCHITECTURE NOTIFICATION ERROR: ' +
                emailException.getMessage() +
                ' | Line: ' +
                emailException.getLineNumber()
            );
        }
    }
}