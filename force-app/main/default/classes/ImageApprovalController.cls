/**
 * @description Controller for Architecture Design LWC and Public Site.
 *
 * Responsibilities:
 * - Create Architecture Design
 * - Link uploaded files
 * - Retrieve submission history
 * - Retrieve Architecture Design using secure token
 * - Capture Approved / Changes Requested response
 *
 * IMPORTANT:
 * No email is sent directly from this controller.
 *
 * Emails are handled globally through:
 *
 * ArchitectureDesignTrigger
 *          ↓
 * ArchitectureDesignNotificationHandler
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ImageApprovalController {

    private static final String ERROR_UNSUPPORTED_RECORD_TYPE =
        'Image approval is supported only for Arelia opportunities.';

    private static final String ERROR_UNSUPPORTED_PARENT =
        'Architecture Design is supported only for Opportunity or the configured Project object.';

    private static final String STATUS_SENT =
        'Sent';

    private static final String STATUS_APPROVED =
        'Approved';

    private static final String STATUS_CHANGES_REQUESTED =
        'Changes Requested';

    private static final String ARELIA_OPPORTUNITY_RECORD_TYPE_NAME =
        'Arelia';

    private static Id cachedAreliaOpportunityRecordTypeId;

    // ========================================================================
    // WRAPPER
    // ========================================================================

    public class DesignWrapper {

        @AuraEnabled
        public String id;

        @AuraEnabled
        public String title;

        @AuraEnabled
        public String status;

        @AuraEnabled
        public String statusClass;

        @AuraEnabled
        public String clientComments;

        @AuraEnabled
        public Date createdDate;

        @AuraEnabled
        public Boolean managerApproved;

        @AuraEnabled
        public String managerComments;
    }

    // ========================================================================
    // 1. SUBMIT ARCHITECTURE DESIGN
    // ========================================================================

    @AuraEnabled
    public static void sendDesignBundle(
        Id recordId,
        List<String> fileIds,
        Decimal budget
    ) {

        if (recordId == null) {
            throw new AuraHandledException(
                'Parent record Id is required.'
            );
        }

        if (
            fileIds == null ||
            fileIds.isEmpty()
        ) {
            throw new AuraHandledException(
                'Please upload at least one Architecture Design file.'
            );
        }

        try {

            // Validate Opportunity / Project
            validateParentRecord(recordId);

            // ================================================================
            // STEP 1
            //
            // Create Architecture Design WITHOUT setting Status__c.
            //
            // Do NOT use Draft because Draft is not an allowed value
            // in your restricted Status__c picklist.
            // ================================================================
            Architecture_Design__c design =
                createDesignRecord(
                    recordId,
                    fileIds[0],
                    budget
                );

            // ================================================================
            // STEP 2
            // Link all uploaded files to Architecture Design.
            // ================================================================
            linkFilesToDesign(
                design.Id,
                fileIds
            );

            // ================================================================
            // STEP 3
            // Remove original parent links.
            // ================================================================
            cleanupParentFiles(
                recordId,
                fileIds
            );

            // ================================================================
            // STEP 4
            //
            // Set Status = Sent only AFTER files are linked.
            //
            // This update fires ArchitectureDesignTrigger.
            //
            // Trigger:
            // old Status = null/default
            // new Status = Sent
            //
            // ArchitectureDesignNotificationHandler sends Customer email.
            // ================================================================
            markDesignAsSent(
                design.Id
            );

            // ================================================================
            // STEP 5
            // Preserve existing Opportunity flag.
            // ================================================================
            updateOpportunityStatus(
                recordId
            );

        } catch (AuraHandledException e) {

            throw e;

        } catch (Exception e) {

            throw new AuraHandledException(
                'Error submitting Architecture Design: ' +
                e.getMessage()
            );
        }
    }

    // ========================================================================
    // CREATE ARCHITECTURE DESIGN
    // ========================================================================

    private static Architecture_Design__c createDesignRecord(
        Id recordId,
        String mainFileId,
        Decimal budget
    ) {

        Architecture_Design__c design =
            new Architecture_Design__c();

        linkDesignToParent(
            design,
            recordId
        );

        design.Secure_Token__c =
            UUID.randomUUID().toString();

        design.Related_File_Id__c =
            mainFileId;

        design.Architecture_Budget__c =
            budget;

        /*
         * VERY IMPORTANT
         *
         * Do NOT set:
         *
         * design.Status__c = 'Draft';
         *
         * Draft is not present in the restricted Status__c picklist.
         *
         * Status will be set to Sent after all files are linked.
         */

        insert design;

        return design;
    }

    // ========================================================================
    // LINK FILES
    // ========================================================================

    private static void linkFilesToDesign(
        Id designId,
        List<String> fileIds
    ) {

        if (
            designId == null ||
            fileIds == null ||
            fileIds.isEmpty()
        ) {
            return;
        }

        List<ContentDocumentLink> links =
            new List<ContentDocumentLink>();

        for (String fileId : fileIds) {

            if (String.isBlank(fileId)) {
                continue;
            }

            ContentDocumentLink link =
                new ContentDocumentLink();

            link.LinkedEntityId =
                designId;

            link.ContentDocumentId =
                fileId;

            link.ShareType =
                'V';

            link.Visibility =
                'AllUsers';

            links.add(link);
        }

        if (!links.isEmpty()) {
            insert links;
        }
    }

    // ========================================================================
    // REMOVE FILE LINKS FROM ORIGINAL PARENT
    // ========================================================================

    private static void cleanupParentFiles(
        Id recordId,
        List<String> fileIds
    ) {

        if (
            recordId == null ||
            fileIds == null ||
            fileIds.isEmpty()
        ) {
            return;
        }

        List<ContentDocumentLink> linksToDelete = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId
            AND ContentDocumentId IN :fileIds
        ];

        if (!linksToDelete.isEmpty()) {
            delete linksToDelete;
        }
    }

    // ========================================================================
    // MARK ARCHITECTURE DESIGN AS SENT
    // ========================================================================

    private static void markDesignAsSent(
        Id designId
    ) {

        if (designId == null) {
            return;
        }

        update new Architecture_Design__c(
            Id = designId,
            Status__c = STATUS_SENT
        );
    }

    // ========================================================================
    // 2. SUBMISSION HISTORY
    // ========================================================================

    @AuraEnabled(cacheable=true)
    public static List<DesignWrapper> getRelatedImages(
        Id recordId
    ) {

        List<DesignWrapper> designList =
            new List<DesignWrapper>();

        if (recordId == null) {
            return designList;
        }

        List<Architecture_Design__c> designs = [
            SELECT
                Id,
                Name,
                Status__c,
                Comments__c,
                CreatedDate,
                Manager_Approval__c,
                Manager_Comments__c
            FROM Architecture_Design__c
            WHERE Opportunity__c = :recordId
            OR Project__c = :recordId
            ORDER BY CreatedDate DESC
        ];

        for (
            Architecture_Design__c design :
            designs
        ) {

            DesignWrapper wrapper =
                new DesignWrapper();

            wrapper.id =
                design.Id;

            wrapper.title =
                design.Name;

            wrapper.createdDate =
                design.CreatedDate.date();

            wrapper.status =
                design.Status__c;

            wrapper.clientComments =
                design.Comments__c;

            wrapper.managerApproved =
                design.Manager_Approval__c;

            wrapper.managerComments =
                design.Manager_Comments__c;

            wrapper.statusClass =
                getBadgeClass(
                    design.Status__c
                );

            designList.add(wrapper);
        }

        return designList;
    }

    private static String getBadgeClass(
        String status
    ) {

        if (status == STATUS_APPROVED) {
            return 'slds-badge slds-theme_success';
        }

        if (
            status ==
            STATUS_CHANGES_REQUESTED
        ) {
            return 'slds-badge slds-theme_error';
        }

        return 'slds-badge slds-theme_warning';
    }

    // ========================================================================
    // 3. PUBLIC CUSTOMER APPROVAL PAGE
    // ========================================================================

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getFileByToken(
        String token
    ) {

        if (String.isBlank(token)) {
            throw new AuraHandledException(
                'Invalid Link or Record Not Found'
            );
        }

        try {

            Architecture_Design__c design = [
                SELECT
                    Id,
                    Status__c,
                    Comments__c,
                    Project__r.Name,
                    Opportunity__r.Name,
                    Opportunity__r.Lead_Name__c
                FROM Architecture_Design__c
                WHERE Secure_Token__c = :token
                LIMIT 1
            ];

            Map<String, String> result =
                new Map<String, String>();

            result.put(
                'status',
                design.Status__c
            );

            result.put(
                'comments',
                design.Comments__c
            );

            result.put(
                'projectName',
                getExternalProjectName(
                    design
                )
            );

            String clientName =
                'Valued Client';

            if (
                design.Opportunity__r != null &&
                String.isNotBlank(
                    design.Opportunity__r
                        .Lead_Name__c
                )
            ) {
                clientName =
                    design.Opportunity__r
                        .Lead_Name__c;
            }

            result.put(
                'clientName',
                clientName
            );

            return result;

        } catch (Exception e) {

            throw new AuraHandledException(
                'Invalid Link or Record Not Found'
            );
        }
    }

    // ========================================================================
    // 4. CUSTOMER RESPONSE
    // ========================================================================

    @AuraEnabled
    public static void submitDecision(
        String token,
        String status,
        String comments
    ) {

        if (String.isBlank(token)) {
            throw new AuraHandledException(
                'Invalid Architecture Design token.'
            );
        }

        try {

            validateCustomerDecision(status);

            Architecture_Design__c design = [
                SELECT
                    Id,
                    Status__c,
                    Comments__c,
                    Opportunity__c,
                    Opportunity__r.RecordTypeId
                FROM Architecture_Design__c
                WHERE Secure_Token__c = :token
                LIMIT 1
            ];

            if (
                design.Opportunity__r != null &&
                !isAreliaOpportunityRecordType(
                    design.Opportunity__r
                        .RecordTypeId
                )
            ) {
                throw new AuraHandledException(
                    ERROR_UNSUPPORTED_RECORD_TYPE
                );
            }

            // ================================================================
            // ONLY UPDATE CUSTOMER RESPONSE
            // ================================================================

            design.Status__c =
                status;

            if (String.isNotBlank(comments)) {

                design.Comments__c =
                    comments;

            } else if (
                status == STATUS_APPROVED
            ) {

                design.Comments__c =
                    'Approved By Client';

            } else {

                design.Comments__c =
                    'Changes Requested By Client';
            }

            /*
             * This update fires ArchitectureDesignTrigger.
             *
             * Approved
             *      ↓
             * Supervisor receives email
             *
             * Changes Requested
             *      ↓
             * Supervisor receives email
             */

            update design;

        } catch (AuraHandledException e) {

            throw e;

        } catch (Exception e) {

            throw new AuraHandledException(
                e.getMessage()
            );
        }
    }

    private static void validateCustomerDecision(
        String status
    ) {

        if (
            status != STATUS_APPROVED &&
            status != STATUS_CHANGES_REQUESTED
        ) {
            throw new AuraHandledException(
                'Invalid Architecture Design response. ' +
                'Allowed values are Approved or Changes Requested.'
            );
        }
    }

    // ========================================================================
    // PROJECT NAME
    // ========================================================================

    @TestVisible
    private static String getExternalProjectName(
        Architecture_Design__c design
    ) {

        String projectName =
            'Architectural Design';

        if (
            design != null &&
            design.Project__r != null
        ) {

            projectName =
                design.Project__r.Name;

        } else if (
            design != null &&
            design.Opportunity__r != null
        ) {

            projectName =
                design.Opportunity__r.Name;
        }

        return projectName;
    }

    // ========================================================================
    // PARENT VALIDATION
    // ========================================================================

    private static void validateParentRecord(
        Id recordId
    ) {

        String objectApiName =
            recordId
                .getSObjectType()
                .getDescribe()
                .getName();

        if (objectApiName == 'Opportunity') {

            assertAreliaOpportunityRecordType(
                recordId
            );

            return;
        }

        if (isConfiguredProjectObject(recordId)) {
            return;
        }

        throw new AuraHandledException(
            ERROR_UNSUPPORTED_PARENT
        );
    }

    // ========================================================================
    // RECORD TYPE
    // ========================================================================

    private static void assertAreliaOpportunityRecordType(
        Id recordId
    ) {

        Id areliaRecordTypeId =
            getAreliaOpportunityRecordTypeId();

        if (areliaRecordTypeId == null) {
            throw new AuraHandledException(
                ERROR_UNSUPPORTED_RECORD_TYPE
            );
        }

        List<Opportunity> opportunities = [
            SELECT Id
            FROM Opportunity
            WHERE Id = :recordId
            AND RecordTypeId =
                :areliaRecordTypeId
            LIMIT 1
        ];

        if (opportunities.isEmpty()) {
            throw new AuraHandledException(
                ERROR_UNSUPPORTED_RECORD_TYPE
            );
        }
    }

    private static Boolean isAreliaOpportunityRecordType(
        Id recordTypeId
    ) {

        if (recordTypeId == null) {
            return false;
        }

        Id areliaRecordTypeId =
            getAreliaOpportunityRecordTypeId();

        return
            areliaRecordTypeId != null &&
            recordTypeId == areliaRecordTypeId;
    }

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
            return null;
        }

        cachedAreliaOpportunityRecordTypeId =
            recordTypeInfo.getRecordTypeId();

        return cachedAreliaOpportunityRecordTypeId;
    }

    // ========================================================================
    // LINK PARENT
    // ========================================================================

    private static void linkDesignToParent(
        Architecture_Design__c design,
        Id recordId
    ) {

        String objectApiName =
            recordId
                .getSObjectType()
                .getDescribe()
                .getName();

        if (objectApiName == 'Opportunity') {

            design.Opportunity__c =
                recordId;

            return;
        }

        if (isConfiguredProjectObject(recordId)) {

            design.Project__c =
                recordId;

            return;
        }

        throw new AuraHandledException(
            ERROR_UNSUPPORTED_PARENT
        );
    }

    private static Boolean isConfiguredProjectObject(
        Id recordId
    ) {

        if (recordId == null) {
            return false;
        }

        String inputObjectApiName =
            recordId
                .getSObjectType()
                .getDescribe()
                .getName();

        List<Schema.SObjectType> referenceTypes = Architecture_Design__c.Project__c.getDescribe().getReferenceTo();

        for (
            Schema.SObjectType referenceType :
            referenceTypes
        ) {

            String referencedObjectApiName =
                referenceType
                    .getDescribe()
                    .getName();

            if (
                inputObjectApiName ==
                referencedObjectApiName
            ) {
                return true;
            }
        }

        return false;
    }

    // ========================================================================
    // OPPORTUNITY FLAG
    // ========================================================================

    private static void updateOpportunityStatus(
        Id recordId
    ) {

        if (recordId == null) {
            return;
        }

        String objectApiName =
            recordId
                .getSObjectType()
                .getDescribe()
                .getName();

        if (objectApiName != 'Opportunity') {
            return;
        }

        update new Opportunity(
            Id = recordId,
            Architecture_Client_Approval_Sent__c = true
        );
    }
}