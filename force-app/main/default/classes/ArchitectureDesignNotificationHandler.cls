/**
 * @description Global email notification handler for Architecture Design.
 *
 * Handles:
 * 1. Architecture Design submitted -> email Customer
 * 2. Customer Approved -> email Supervisor
 * 3. Customer Changes Requested -> email Supervisor
 *
 * This class is called only from ArchitectureDesignTrigger so that
 * notifications work globally for LWC, Mobile, Experience Site,
 * API, Flow, Apex and other integrations.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ArchitectureDesignNotificationHandler {

    private static final String STATUS_SENT = 'Sent';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_CHANGES_REQUESTED = 'Changes Requested';

    private static final String DEFAULT_CLIENT_NAME = 'Valued Client';
    private static final String DEFAULT_SUPERVISOR_NAME = 'Enrollment Team';

    private static final String ARELIA_OPPORTUNITY_RECORD_TYPE_NAME = 'Arelia';

    private static Id cachedAreliaOpportunityRecordTypeId;

    // ========================================================================
    // TRIGGER ENTRY POINT
    // ========================================================================

    /**
     * @description Handles Architecture Design status changes.
     * @param newList New Architecture Design records.
     * @param oldMap Previous Architecture Design records.
     */
    public static void onAfterUpdate(
        List<Architecture_Design__c> newList,
        Map<Id, Architecture_Design__c> oldMap
    ) {
        if (
            newList == null ||
            newList.isEmpty() ||
            oldMap == null
        ) {
            return;
        }

        Set<Id> submittedDesignIds = new Set<Id>();
        Set<Id> customerResponseDesignIds = new Set<Id>();

        for (Architecture_Design__c newDesign : newList) {

            Architecture_Design__c oldDesign =
                oldMap.get(newDesign.Id);

            if (oldDesign == null) {
                continue;
            }

            // ================================================================
            // EVENT 1:
            // Architecture Design submitted to Customer
            //
            // Example:
            // Draft -> Sent
            // ================================================================
            if (
                newDesign.Status__c == STATUS_SENT &&
                oldDesign.Status__c != STATUS_SENT
            ) {
                submittedDesignIds.add(newDesign.Id);
            }

            // ================================================================
            // EVENT 2:
            // Customer response received
            //
            // Sent -> Approved
            // Sent -> Changes Requested
            // Changes Requested -> Approved
            // ================================================================
            if (
                isCustomerResponseStatus(newDesign.Status__c) &&
                newDesign.Status__c != oldDesign.Status__c
            ) {
                customerResponseDesignIds.add(newDesign.Id);
            }
        }

        // Customer receives Architecture Design package.
        if (!submittedDesignIds.isEmpty()) {
            sendSubmissionEmails(submittedDesignIds);
        }

        // Supervisor receives Customer response.
        if (!customerResponseDesignIds.isEmpty()) {
            sendCustomerResponseEmails(customerResponseDesignIds);
        }
    }

    // ========================================================================
    // STATUS HELPERS
    // ========================================================================

    private static Boolean isCustomerResponseStatus(String status) {

        return status == STATUS_APPROVED ||
            status == STATUS_CHANGES_REQUESTED;
    }

    // ========================================================================
    // ARCHITECTURE DESIGN SUBMITTED -> CUSTOMER EMAIL
    // ========================================================================

    private static void sendSubmissionEmails(
        Set<Id> designIds
    ) {
        try {

            Map<Id, Architecture_Design__c> designMap =
                queryDesignData(designIds);

            if (designMap.isEmpty()) {
                return;
            }

            EmailTemplate template = getEmailTemplate(
                Label.Client_Image_Approval_Template
            );

            if (template == null) {

                System.debug(
                    LoggingLevel.ERROR,
                    'Client Image Approval email template not found.'
                );

                return;
            }

            Map<Id, List<Id>> attachmentMap =
                mapDesignToFileVersions(designIds);

            Id orgWideEmailId =
                getDefaultOrgWideEmailAddressId();

            List<Messaging.SingleEmailMessage> emails =
                new List<Messaging.SingleEmailMessage>();

            for (Id designId : designIds) {

                Architecture_Design__c design =
                    designMap.get(designId);

                if (
                    design == null ||
                    !shouldHandleDesign(design)
                ) {
                    continue;
                }

                String clientEmail =
                    getClientEmail(design);

                if (String.isBlank(clientEmail)) {

                    System.debug(
                        LoggingLevel.WARN,
                        'Customer email not found. ' +
                        'Architecture Design Id: ' +
                        design.Id
                    );

                    continue;
                }

                String clientName =
                    getClientName(design);

                String approvalLink =
                    buildClientApprovalLink(
                        design.Secure_Token__c
                    );

                String htmlBody =
                    safeReplace(
                        template.HtmlValue,
                        '[APPROVAL_LINK]',
                        approvalLink
                    );

                htmlBody =
                    safeReplace(
                        htmlBody,
                        '[CLIENT_NAME]',
                        clientName
                    );

                String subject =
                    safeReplace(
                        template.Subject,
                        '[FILE_TITLE]',
                        'New Design Submission'
                    );

                if (String.isBlank(subject)) {
                    subject = 'New Design Submission';
                }

                Messaging.SingleEmailMessage mail =
                    new Messaging.SingleEmailMessage();

                mail.setToAddresses(
                    new List<String>{
                        clientEmail
                    }
                );

                mail.setSubject(subject);
                mail.setHtmlBody(htmlBody);
                mail.setSaveAsActivity(false);

                if (orgWideEmailId != null) {
                    mail.setOrgWideEmailAddressId(
                        orgWideEmailId
                    );
                }

                // Attach all linked Architecture Design files.
                if (
                    attachmentMap.containsKey(design.Id) &&
                    !attachmentMap.get(design.Id).isEmpty()
                ) {
                    mail.setEntityAttachments(
                        attachmentMap.get(design.Id)
                    );
                }

                emails.add(mail);
            }

            if (!emails.isEmpty()) {

                Messaging.sendEmail(
                    emails,
                    false
                );
            }

        } catch (Exception e) {

            System.debug(
                LoggingLevel.ERROR,
                'Architecture submission email failed: ' +
                e.getMessage() +
                ' | Line: ' +
                e.getLineNumber()
            );
        }
    }

    // ========================================================================
    // CUSTOMER RESPONSE -> SUPERVISOR EMAIL
    // ========================================================================

    private static void sendCustomerResponseEmails(
        Set<Id> designIds
    ) {
        try {

            Map<Id, Architecture_Design__c> designMap =
                queryDesignData(designIds);

            if (designMap.isEmpty()) {
                return;
            }

            EmailTemplate template =
                getEmailTemplate(
                    Label.Client_Response_Notification_Template
                );

            if (template == null) {

                System.debug(
                    LoggingLevel.ERROR,
                    'Client Response Notification email template not found.'
                );

                return;
            }

            Map<Id, List<Id>> attachmentMap =
                mapDesignToFileVersions(designIds);

            Id orgWideEmailId =
                getDefaultOrgWideEmailAddressId();

            List<Messaging.SingleEmailMessage> emails =
                new List<Messaging.SingleEmailMessage>();

            for (Id designId : designIds) {

                Architecture_Design__c design =
                    designMap.get(designId);

                if (
                    design == null ||
                    !shouldHandleDesign(design)
                ) {
                    continue;
                }

                String supervisorEmail =
                    getSupervisorEmail(design);

                if (String.isBlank(supervisorEmail)) {

                    System.debug(
                        LoggingLevel.WARN,
                        'Supervisor email not found. ' +
                        'Architecture Design Id: ' +
                        design.Id
                    );

                    continue;
                }

                Messaging.SingleEmailMessage mail =
                    buildCustomerResponseEmail(
                        design,
                        template,
                        supervisorEmail,
                        orgWideEmailId
                    );

                // Attach Architecture Design files.
                if (
                    attachmentMap.containsKey(design.Id) &&
                    !attachmentMap.get(design.Id).isEmpty()
                ) {
                    mail.setEntityAttachments(
                        attachmentMap.get(design.Id)
                    );
                }

                emails.add(mail);
            }

            if (!emails.isEmpty()) {

                Messaging.sendEmail(
                    emails,
                    false
                );
            }

        } catch (Exception e) {

            System.debug(
                LoggingLevel.ERROR,
                'Customer response email failed: ' +
                e.getMessage() +
                ' | Line: ' +
                e.getLineNumber()
            );
        }
    }

    // ========================================================================
    // BUILD CUSTOMER RESPONSE EMAIL
    // ========================================================================

    private static Messaging.SingleEmailMessage
        buildCustomerResponseEmail(
            Architecture_Design__c design,
            EmailTemplate template,
            String supervisorEmail,
            Id orgWideEmailId
        ) {

        String projectName =
            getProjectName(design);

        String clientName =
            getClientName(design);

        String supervisorName =
            getSupervisorName(design);

        String comments =
            String.isNotBlank(design.Comments__c)
                ? design.Comments__c
                : 'No comments provided.';

        String projectDescription = '';
        String siteSpace = '';
        String clientEmail = '';
        String clientPhone = 'N/A';

        if (design.Opportunity__r != null) {

            projectDescription =
                safeValue(
                    design.Opportunity__r
                        .Project_Description__c
                );

            siteSpace =
                safeValue(
                    design.Opportunity__r
                        .Site_Space__c
                );

            // Primary Contact email is used in your existing
            // Client Response email template.
            if (
                design.Opportunity__r
                    .Primary_Contact__r != null
            ) {
                clientEmail =
                    safeValue(
                        design.Opportunity__r
                            .Primary_Contact__r.Email
                    );
            }

            // Fallback to Opportunity Email__c.
            if (
                String.isBlank(clientEmail) &&
                String.isNotBlank(
                    design.Opportunity__r.Email__c
                )
            ) {
                clientEmail =
                    design.Opportunity__r.Email__c;
            }

            if (
                String.isNotBlank(
                    design.Opportunity__r
                        .Lead_Phone__c
                )
            ) {
                clientPhone =
                    design.Opportunity__r
                        .Lead_Phone__c;
            }
        }

        String subject =
            safeReplace(
                template.Subject,
                '[CLIENT_NAME]',
                clientName
            );

        subject =
            safeReplace(
                subject,
                '[DECISION]',
                design.Status__c
            );

        String htmlBody =
            safeReplace(
                template.HtmlValue,
                '[PROJECT_NAME]',
                projectName
            );

        htmlBody =
            safeReplace(
                htmlBody,
                '[DECISION]',
                design.Status__c
            );

        htmlBody =
            safeReplace(
                htmlBody,
                '[COMMENTS]',
                comments
            );

        htmlBody =
            safeReplace(
                htmlBody,
                '[SUPERVISOR_NAME]',
                supervisorName
            );

        htmlBody =
            safeReplace(
                htmlBody,
                '[PROJECT_DESCRIPTION]',
                projectDescription
            );

        htmlBody =
            safeReplace(
                htmlBody,
                '[SITE_SPACE]',
                siteSpace
            );

        htmlBody =
            safeReplace(
                htmlBody,
                '[CLIENT_EMAIL]',
                clientEmail
            );

        htmlBody =
            safeReplace(
                htmlBody,
                '[CLIENT_MOBILE]',
                clientPhone
            );

        htmlBody =
            safeReplace(
                htmlBody,
                '[CLIENT_NAME]',
                clientName
            );

        Messaging.SingleEmailMessage mail =
            new Messaging.SingleEmailMessage();

        mail.setToAddresses(
            new List<String>{
                supervisorEmail
            }
        );

        mail.setSubject(subject);
        mail.setHtmlBody(htmlBody);
        mail.setSaveAsActivity(false);

        if (orgWideEmailId != null) {
            mail.setOrgWideEmailAddressId(
                orgWideEmailId
            );
        }

        return mail;
    }

    // ========================================================================
    // ARCHITECTURE DESIGN QUERY
    // ========================================================================

    /**
     * IMPORTANT:
     *
     * Do NOT add:
     *
     * Project__r.Client_Email__c
     *
     * because Architecture_Design__c.Project__c currently resolves
     * to sf_devops__Project__c in your org and that object does not
     * contain Client_Email__c.
     */
    private static Map<Id, Architecture_Design__c>
        queryDesignData(
            Set<Id> designIds
        ) {

        return new Map<Id, Architecture_Design__c>([
            SELECT
                Id,
                Name,
                Status__c,
                Comments__c,
                Secure_Token__c,
                Related_File_Id__c,
                Architecture_Budget__c,

                Opportunity__c,
                Opportunity__r.RecordTypeId,
                Opportunity__r.Name,
                Opportunity__r.Email__c,
                Opportunity__r.Lead_Name__c,
                Opportunity__r.Project_Description__c,
                Opportunity__r.Site_Space__c,
                Opportunity__r.Lead_Phone__c,

                Opportunity__r.Primary_Contact__r.Email,

                Opportunity__r.Supervisor_User_Email__c,
                Opportunity__r.Supervisor_User__r.FirstName,
                Opportunity__r.Supervisor_User__r.LastName,
                Opportunity__r.Supervisor_User__r.Email,

                Project__c,
                Project__r.Name

            FROM Architecture_Design__c
            WHERE Id IN :designIds
        ]);
    }

    // ========================================================================
    // FILE ATTACHMENT LOGIC
    // ========================================================================

    /**
     * @description Maps Architecture Design Id -> latest ContentVersion Ids.
     */
    private static Map<Id, List<Id>>
        mapDesignToFileVersions(
            Set<Id> designIds
        ) {

        Map<Id, Set<Id>> designToDocumentIds =
            new Map<Id, Set<Id>>();

        Set<Id> allDocumentIds =
            new Set<Id>();

        for (
            ContentDocumentLink link : [
                SELECT
                    LinkedEntityId,
                    ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :designIds
            ]
        ) {

            if (
                !designToDocumentIds.containsKey(
                    link.LinkedEntityId
                )
            ) {
                designToDocumentIds.put(
                    link.LinkedEntityId,
                    new Set<Id>()
                );
            }

            designToDocumentIds
                .get(link.LinkedEntityId)
                .add(link.ContentDocumentId);

            allDocumentIds.add(
                link.ContentDocumentId
            );
        }

        Map<Id, List<Id>> result =
            new Map<Id, List<Id>>();

        if (allDocumentIds.isEmpty()) {
            return result;
        }

        Map<Id, Id> documentToVersionId =
            new Map<Id, Id>();

        for (
            ContentVersion version : [
                SELECT
                    Id,
                    ContentDocumentId
                FROM ContentVersion
                WHERE ContentDocumentId IN :allDocumentIds
                AND IsLatest = true
            ]
        ) {
            documentToVersionId.put(
                version.ContentDocumentId,
                version.Id
            );
        }

        for (
            Id designId :
            designToDocumentIds.keySet()
        ) {

            List<Id> versionIds =
                new List<Id>();

            for (
                Id documentId :
                designToDocumentIds.get(designId)
            ) {

                if (
                    documentToVersionId.containsKey(
                        documentId
                    )
                ) {
                    versionIds.add(
                        documentToVersionId.get(
                            documentId
                        )
                    );
                }
            }

            if (!versionIds.isEmpty()) {
                result.put(
                    designId,
                    versionIds
                );
            }
        }

        return result;
    }

    // ========================================================================
    // CUSTOMER DETAILS
    // ========================================================================

    private static String getClientEmail(
        Architecture_Design__c design
    ) {

        if (design == null) {
            return null;
        }

        // --------------------------------------------------------------------
        // PRIMARY SOURCE:
        // Opportunity Email__c
        // --------------------------------------------------------------------
        if (
            design.Opportunity__r != null &&
            String.isNotBlank(
                design.Opportunity__r.Email__c
            )
        ) {
            return design.Opportunity__r.Email__c;
        }

        // --------------------------------------------------------------------
        // FALLBACK:
        // Opportunity Primary Contact
        // --------------------------------------------------------------------
        if (
            design.Opportunity__r != null &&
            design.Opportunity__r.Primary_Contact__r != null &&
            String.isNotBlank(
                design.Opportunity__r
                    .Primary_Contact__r.Email
            )
        ) {
            return design.Opportunity__r
                .Primary_Contact__r.Email;
        }

        // --------------------------------------------------------------------
        // PROJECT FALLBACK
        //
        // We dynamically check whether the ACTUAL Project object
        // contains Client_Email__c.
        //
        // This prevents compile errors when Project__c points to:
        // sf_devops__Project__c
        //
        // If later Project__c points to your custom Project__c and it
        // contains Client_Email__c, this method will automatically use it.
        // --------------------------------------------------------------------
        if (design.Project__c != null) {
            return getProjectClientEmail(
                design.Project__c
            );
        }

        return null;
    }

    /**
     * Dynamically retrieves Client_Email__c only when that field
     * actually exists on the referenced Project object.
     */
    private static String getProjectClientEmail(
        Id projectId
    ) {

        if (projectId == null) {
            return null;
        }

        try {

            Schema.DescribeSObjectResult projectDescribe =
                projectId
                    .getSObjectType()
                    .getDescribe();

            Map<String, Schema.SObjectField> projectFields =
                projectDescribe
                    .fields
                    .getMap();

            // sf_devops__Project__c does not currently have this field.
            // Therefore safely return null rather than fail compilation.
            if (
                !projectFields.containsKey(
                    'Client_Email__c'
                )
            ) {
                return null;
            }

            String objectApiName =
                projectDescribe.getName();

            String queryString =
                'SELECT Client_Email__c ' +
                'FROM ' +
                objectApiName +
                ' WHERE Id = :projectId LIMIT 1';

            List<SObject> projectRecords =
                Database.query(queryString);

            if (projectRecords.isEmpty()) {
                return null;
            }

            Object emailValue =
                projectRecords[0].get(
                    'Client_Email__c'
                );

            return emailValue == null
                ? null
                : String.valueOf(emailValue);

        } catch (Exception e) {

            System.debug(
                LoggingLevel.WARN,
                'Unable to retrieve Project Client Email: ' +
                e.getMessage()
            );

            return null;
        }
    }

    private static String getClientName(
        Architecture_Design__c design
    ) {

        if (
            design != null &&
            design.Opportunity__r != null &&
            String.isNotBlank(
                design.Opportunity__r.Lead_Name__c
            )
        ) {
            return design.Opportunity__r.Lead_Name__c;
        }

        return DEFAULT_CLIENT_NAME;
    }

    // ========================================================================
    // SUPERVISOR DETAILS
    // ========================================================================

    private static String getSupervisorEmail(
        Architecture_Design__c design
    ) {

        if (
            design == null ||
            design.Opportunity__r == null
        ) {
            return null;
        }

        // Preserve your existing custom Supervisor email field first.
        if (
            String.isNotBlank(
                design.Opportunity__r
                    .Supervisor_User_Email__c
            )
        ) {
            return design.Opportunity__r
                .Supervisor_User_Email__c;
        }

        // Fallback to actual Salesforce User Email.
        if (
            design.Opportunity__r
                .Supervisor_User__r != null &&
            String.isNotBlank(
                design.Opportunity__r
                    .Supervisor_User__r.Email
            )
        ) {
            return design.Opportunity__r
                .Supervisor_User__r.Email;
        }

        return null;
    }

    private static String getSupervisorName(
        Architecture_Design__c design
    ) {

        if (
            design == null ||
            design.Opportunity__r == null ||
            design.Opportunity__r
                .Supervisor_User__r == null
        ) {
            return DEFAULT_SUPERVISOR_NAME;
        }

        String firstName =
            design.Opportunity__r
                .Supervisor_User__r.FirstName;

        String lastName =
            design.Opportunity__r
                .Supervisor_User__r.LastName;

        String fullName =
            (
                safeValue(firstName) +
                ' ' +
                safeValue(lastName)
            ).trim();

        return String.isNotBlank(fullName)
            ? fullName
            : DEFAULT_SUPERVISOR_NAME;
    }

    // ========================================================================
    // PROJECT NAME
    // ========================================================================

    private static String getProjectName(
        Architecture_Design__c design
    ) {

        if (
            design != null &&
            design.Opportunity__r != null &&
            String.isNotBlank(
                design.Opportunity__r.Name
            )
        ) {
            return design.Opportunity__r.Name;
        }

        if (
            design != null &&
            design.Project__r != null &&
            String.isNotBlank(
                design.Project__r.Name
            )
        ) {
            return design.Project__r.Name;
        }

        return 'Unknown Project';
    }

    // ========================================================================
    // ARELIA OPPORTUNITY FILTER
    // ========================================================================

    private static Boolean shouldHandleDesign(
        Architecture_Design__c design
    ) {

        if (design == null) {
            return false;
        }

        // Project-based Architecture Design.
        if (design.Opportunity__c == null) {
            return true;
        }

        if (design.Opportunity__r == null) {
            return false;
        }

        Id areliaRecordTypeId =
            getAreliaOpportunityRecordTypeId();

        return
            areliaRecordTypeId != null &&
            design.Opportunity__r.RecordTypeId ==
                areliaRecordTypeId;
    }

    /**
     * Local implementation.
     *
     * IMPORTANT:
     * No AreliaUtility dependency.
     */
    private static Id getAreliaOpportunityRecordTypeId() {

        if (
            cachedAreliaOpportunityRecordTypeId != null
        ) {
            return cachedAreliaOpportunityRecordTypeId;
        }

        Schema.RecordTypeInfo recordTypeInfo =
            Schema.SObjectType.Opportunity
                .getRecordTypeInfosByName()
                .get(
                    ARELIA_OPPORTUNITY_RECORD_TYPE_NAME
                );

        if (recordTypeInfo == null) {

            System.debug(
                LoggingLevel.WARN,
                'Arelia Opportunity Record Type not found.'
            );

            return null;
        }

        cachedAreliaOpportunityRecordTypeId =
            recordTypeInfo.getRecordTypeId();

        return cachedAreliaOpportunityRecordTypeId;
    }

    // ========================================================================
    // EMAIL TEMPLATE
    // ========================================================================

    private static EmailTemplate getEmailTemplate(
        String developerName
    ) {

        if (String.isBlank(developerName)) {
            return null;
        }

        List<EmailTemplate> templates = [
            SELECT
                Id,
                Subject,
                HtmlValue
            FROM EmailTemplate
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];

        return templates.isEmpty()
            ? null
            : templates[0];
    }

    // ========================================================================
    // CUSTOMER APPROVAL LINK
    // ========================================================================

    private static String buildClientApprovalLink(
        String token
    ) {

        String siteBase =
            System.Label.Arelia_Site_Label;

        String pagePath =
            System.Label.Image_Approval;

        if (
            String.isBlank(siteBase) ||
            String.isBlank(pagePath) ||
            String.isBlank(token)
        ) {
            return '#';
        }

        if (
            siteBase.endsWith('/') &&
            pagePath.startsWith('/')
        ) {
            pagePath =
                pagePath.substring(1);

        } else if (
            !siteBase.endsWith('/') &&
            !pagePath.startsWith('/')
        ) {
            pagePath =
                '/' + pagePath;
        }

        return
            siteBase +
            pagePath +
            '?token=' +
            EncodingUtil.urlEncode(
                token,
                'UTF-8'
            );
    }

    // ========================================================================
    // ORG-WIDE EMAIL
    // ========================================================================

    private static Id getDefaultOrgWideEmailAddressId() {

        try {

            List<OrgWideEmailAddress> addresses = [
                SELECT Id
                FROM OrgWideEmailAddress
                WHERE Address =
                    :System.Label.Arelia_OWD
                LIMIT 1
            ];

            return addresses.isEmpty()
                ? null
                : addresses[0].Id;

        } catch (Exception e) {

            System.debug(
                LoggingLevel.WARN,
                'Unable to retrieve Org Wide Email Address: ' +
                e.getMessage()
            );

            return null;
        }
    }

    // ========================================================================
    // STRING UTILITIES
    // ========================================================================

    private static String safeValue(
        String value
    ) {
        return value == null
            ? ''
            : value;
    }

    private static String safeReplace(
        String source,
        String token,
        String value
    ) {

        if (source == null) {
            return '';
        }

        if (String.isBlank(token)) {
            return source;
        }

        return source.replace(
            token,
            value == null ? '' : value
        );
    }
}