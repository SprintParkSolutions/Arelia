/**
 * -----------------------------------------------------------------------------
 * Class Name      : ArchitectureMgrApprovalClientNotifTest
 * Author          : Arelia
 * Created Date    : Oct 16, 2026
 * Description     : Unit tests for
 *                   ArchitectureManagerApprovalClientNotificationTrigger.
 *                   Covers mobile push eligibility, email processing
 *                   conditions, approval transitions, date changes,
 *                   missing relationships, and bulk updates.
 * -----------------------------------------------------------------------------
 */

@IsTest
private class ArchitectureMgrApprovalClientNotifTest {

    private static final String STAGE_QUALIFICATION = 'Qualification';
    private static final Integer BULK_RECORD_COUNT = 5;
    private static final Integer NO_JOBS = 0;
    private static final Integer ONE_JOB = 1;

    /**
     * @description Creates an Opportunity for testing.
     * @param opportunityName Opportunity name.
     * @return Inserted Opportunity record.
     */
    private static Opportunity createOpportunity(String opportunityName) {
        Opportunity testOpportunity = new Opportunity(
            Name = opportunityName,
            StageName = STAGE_QUALIFICATION,
            CloseDate = Date.today().addDays(30)
        );
        insert testOpportunity;
        return testOpportunity;
    }

    /**
     * @description Creates an Architecture Design record.
     * @param opportunityId Related Opportunity ID.
     * @param isApproved Initial manager approval status.
     * @param approvedDate Initial architect approval date.
     * @return Inserted Architecture Design record.
     */
    private static Architecture_Design__c createDesign(
        Id opportunityId,
        Boolean isApproved,
        Date approvedDate
    ) {
        Architecture_Design__c testDesign = new Architecture_Design__c(
            Opportunity__c = opportunityId,
            Manager_Approval__c = isApproved,
            Architect_Approved_Date__c = approvedDate
        );
        insert testDesign;
        return testDesign;
    }

    /**
     * @description Verifies the number of Queueable jobs.
     * @param jobsBefore Count before DML.
     * @param jobsAfter Count after DML.
     * @param expectedJobs Expected difference.
     * @param message Assertion description.
     */
    private static void assertQueueableJobs(
        Integer jobsBefore,
        Integer jobsAfter,
        Integer expectedJobs,
        String message
    ) {
        System.assertEquals(
            expectedJobs,
            jobsAfter - jobsBefore,
            message
        );
    }

    /**
     * @description Verifies manager approval enqueues
     * a mobile push notification.
     */
    @IsTest
    static void managerApprovalEnqueuesNotification() {
        Opportunity testOpportunity = createOpportunity(
            'Manager Approval Test'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            false,
            Date.today()
        );

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();

        testDesign.Manager_Approval__c = true;
        update testDesign;

        Integer jobsAfter = Limits.getQueueableJobs();

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            ONE_JOB,
            'Manager approval should enqueue one notification.'
        );
        Test.stopTest();
    }

    /**
     * @description Verifies populating the approved date
     * after manager approval enqueues a notification.
     */
    @IsTest
    static void approvedDateEnqueuesNotification() {
        Opportunity testOpportunity = createOpportunity(
            'Approved Date Test'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            true,
            null
        );

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();

        testDesign.Architect_Approved_Date__c = Date.today();
        update testDesign;

        Integer jobsAfter = Limits.getQueueableJobs();

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            ONE_JOB,
            'Populating the approved date should enqueue ' +
            'one notification when manager approval is true.'
        );
        Test.stopTest();
    }

    /**
     * @description Verifies approval without an architect
     * approval date does not enqueue mobile push.
     */
    @IsTest
    static void approvalWithoutDateDoesNotNotify() {
        Opportunity testOpportunity = createOpportunity(
            'Approval Without Date'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            false,
            null
        );

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();

        testDesign.Manager_Approval__c = true;
        update testDesign;

        Integer jobsAfter = Limits.getQueueableJobs();

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            NO_JOBS,
            'Mobile push should not be enqueued ' +
            'without an architect approval date.'
        );
        Test.stopTest();
    }

    /**
     * @description Verifies unchanged manager approval
     * does not enqueue another notification.
     */
    @IsTest
    static void unchangedApprovalDoesNotNotify() {
        Opportunity testOpportunity = createOpportunity(
            'Unchanged Approval Test'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            true,
            Date.today()
        );

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();

        testDesign.Manager_Approval__c = true;
        update testDesign;

        Integer jobsAfter = Limits.getQueueableJobs();

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            NO_JOBS,
            'Unchanged manager approval must not ' +
            'enqueue another notification.'
        );
        Test.stopTest();
    }

    /**
     * @description Verifies approval date without manager
     * approval does not enqueue a notification.
     */
    @IsTest
    static void dateWithoutManagerApprovalDoesNotNotify() {
        Opportunity testOpportunity = createOpportunity(
            'Date Without Approval'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            false,
            null
        );

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();

        testDesign.Architect_Approved_Date__c = Date.today();
        update testDesign;

        Integer jobsAfter = Limits.getQueueableJobs();

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            NO_JOBS,
            'Date update without manager approval ' +
            'must not enqueue a notification.'
        );
        Test.stopTest();
    }

    /**
     * @description Verifies approval without an Opportunity
     * does not enqueue mobile push.
     */
    @IsTest
    static void missingOpportunityDoesNotNotify() {
        Architecture_Design__c testDesign = createDesign(
            null,
            false,
            Date.today()
        );

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();

        testDesign.Manager_Approval__c = true;
        update testDesign;

        Integer jobsAfter = Limits.getQueueableJobs();

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            NO_JOBS,
            'Notification should not be enqueued ' +
            'when the Opportunity is missing.'
        );
        Test.stopTest();
    }

    /**
     * @description Verifies multiple approvals enqueue
     * exactly one Queueable job.
     */
    @IsTest
    static void bulkApprovalsEnqueueOneJob() {
        Opportunity testOpportunity = createOpportunity(
            'Bulk Approval Test'
        );

        List<Architecture_Design__c> testDesigns =
            new List<Architecture_Design__c>();

        for (
            Integer index = 0;
            index < BULK_RECORD_COUNT;
            index++
        ) {
            testDesigns.add(new Architecture_Design__c(
                Opportunity__c = testOpportunity.Id,
                Manager_Approval__c = false,
                Architect_Approved_Date__c = Date.today()
            ));
        }

        insert testDesigns;

        for (Architecture_Design__c testDesign : testDesigns) {
            testDesign.Manager_Approval__c = true;
        }

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();

        update testDesigns;

        Integer jobsAfter = Limits.getQueueableJobs();

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            ONE_JOB,
            'Bulk approvals should enqueue exactly ' +
            'one mobile push Queueable job.'
        );
        Test.stopTest();
    }

    /**
     * @description Verifies simultaneous approval and
     * approval-date population enqueue a notification.
     */
    @IsTest
    static void simultaneousApprovalAndDateNotify() {
        Opportunity testOpportunity = createOpportunity(
            'Simultaneous Approval Test'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            false,
            null
        );

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();

        testDesign.Manager_Approval__c = true;
        testDesign.Architect_Approved_Date__c = Date.today();
        update testDesign;

        Integer jobsAfter = Limits.getQueueableJobs();

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            ONE_JOB,
            'Simultaneous approval and date population ' +
            'should enqueue one notification.'
        );
        Test.stopTest();
    }

    /**
     * @description Verifies approval without date is persisted
     * while mobile push remains ineligible.
     */
    @IsTest
    static void managerApprovalWithoutDateProcessesEmailPath() {
        Opportunity testOpportunity = createOpportunity(
            'Email Processing Without Date'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            false,
            null
        );

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();

        testDesign.Manager_Approval__c = true;
        update testDesign;

        Integer jobsAfter = Limits.getQueueableJobs();

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            NO_JOBS,
            'Approval without architect date must not ' +
            'enqueue a mobile push notification.'
        );
        Test.stopTest();

        Architecture_Design__c updatedDesign = [
            SELECT Id, Manager_Approval__c, Opportunity__c
            FROM Architecture_Design__c
            WHERE Id = :testDesign.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            updatedDesign.Manager_Approval__c,
            'Manager approval must be persisted.'
        );

        System.assertEquals(
            testOpportunity.Id,
            updatedDesign.Opportunity__c,
            'Related Opportunity must remain unchanged.'
        );
    }

    /**
     * @description Verifies changing an existing approved
     * date does not enqueue another notification.
     */
    @IsTest
    static void existingApprovedDateChangeDoesNotNotify() {
        Opportunity testOpportunity = createOpportunity(
            'Existing Approved Date Change'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            true,
            Date.today().addDays(-1)
        );

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();

        testDesign.Architect_Approved_Date__c = Date.today();
        update testDesign;

        Integer jobsAfter = Limits.getQueueableJobs();

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            NO_JOBS,
            'Changing an existing approved date ' +
            'must not enqueue another notification.'
        );
        Test.stopTest();
    }

    /**
     * @description Verifies revoking manager approval
     * does not enqueue a notification.
     */
    @IsTest
    static void revokedManagerApprovalDoesNotNotify() {
        Opportunity testOpportunity = createOpportunity(
            'Manager Approval Revocation'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            true,
            Date.today()
        );

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();

        testDesign.Manager_Approval__c = false;
        update testDesign;

        Integer jobsAfter = Limits.getQueueableJobs();

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            NO_JOBS,
            'Revoking manager approval must not ' +
            'enqueue an approval notification.'
        );
        Test.stopTest();
    }

    /**
     * @description Verifies mixed eligible and ineligible
     * approvals enqueue only one Queueable job.
     */
    @IsTest
    static void mixedBulkApprovalsEnqueueOneJob() {
        Opportunity testOpportunity = createOpportunity(
            'Mixed Bulk Approval Test'
        );

        Architecture_Design__c eligibleDesign = createDesign(
            testOpportunity.Id,
            false,
            Date.today()
        );

        Architecture_Design__c missingDateDesign = createDesign(
            testOpportunity.Id,
            false,
            null
        );

        Architecture_Design__c alreadyApprovedDesign = createDesign(
            testOpportunity.Id,
            true,
            Date.today()
        );

        eligibleDesign.Manager_Approval__c = true;
        missingDateDesign.Manager_Approval__c = true;
        alreadyApprovedDesign.Manager_Approval__c = true;

        List<Architecture_Design__c> designsToUpdate =
            new List<Architecture_Design__c>{
                eligibleDesign,
                missingDateDesign,
                alreadyApprovedDesign
            };

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();

        update designsToUpdate;

        Integer jobsAfter = Limits.getQueueableJobs();

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            ONE_JOB,
            'Mixed bulk approval updates must enqueue ' +
            'exactly one Queueable job.'
        );
        Test.stopTest();
    }

    /**
     * @description Creates an Arelia Opportunity with
     * a client Contact and supervisor User.
     * @param opportunityName Opportunity name.
     * @return Inserted Arelia Opportunity.
     */
    private static Opportunity createAreliaOpportunity(
        String opportunityName
    ) {
        Id recordTypeId =
            AreliaUtility.getAreliaOpportunityRecordTypeId();

        System.assertNotEquals(
            null,
            recordTypeId,
            'Arelia Opportunity record type must exist.'
        );

        Contact client = new Contact(
            LastName = 'Architecture Test Client',
            Email = 'architecture.client@example.com'
        );
        insert client;

        Opportunity testOpportunity = new Opportunity(
            Name = opportunityName,
            StageName = STAGE_QUALIFICATION,
            CloseDate = Date.today().addDays(30),
            RecordTypeId = recordTypeId,
            Primary_Contact__c = client.Id,
            Supervisor_User__c = UserInfo.getUserId()
        );

        Schema.DescribeFieldResult descriptionField =
            Opportunity.Project_Description__c.getDescribe();

        if (descriptionField.isCreateable()) {
            testOpportunity.Project_Description__c =
                'Residential architecture design project';
        }

        Schema.DescribeFieldResult clientNameField =
            Opportunity.Lead_Name__c.getDescribe();

        if (clientNameField.isCreateable()) {
            testOpportunity.Lead_Name__c =
                'Architecture Test Client';
        }

        insert testOpportunity;
        return testOpportunity;
    }

    /**
     * @description Ensures required notification templates
     * exist without assuming an exact record count.
     * Existing org templates can be visible to tests.
     */
    private static void createNotificationTemplates() {
        Set<String> templateNames = new Set<String>{
            System.Label.Client_Final_Response_Template,
            System.Label.Manager_Response_Notification_Template
        };

        templateNames.remove(null);
        templateNames.remove('');

        System.assert(
            !templateNames.isEmpty(),
            'Notification template labels must be configured.'
        );

        Set<String> existingNames = new Set<String>();

        for (EmailTemplate existingTemplate : [
            SELECT DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName IN :templateNames
        ]) {
            existingNames.add(existingTemplate.DeveloperName);
        }

        List<EmailTemplate> templatesToCreate =
            new List<EmailTemplate>();

        Integer templateIndex = 0;

        for (String developerName : templateNames) {
            if (existingNames.contains(developerName)) {
                continue;
            }

            templateIndex++;

            templatesToCreate.add(new EmailTemplate(
                Name = 'Architecture Notification Test ' +
                    String.valueOf(templateIndex),
                DeveloperName = developerName,
                FolderId = UserInfo.getUserId(),
                TemplateType = 'custom',
                Subject = 'Architecture Approved - [PROJECT_NAME]',
                HtmlValue =
                    '<html><body>' +
                    '<p>Dear [CLIENT_NAME],</p>' +
                    '<p>Project: [PROJECT_NAME]</p>' +
                    '<p>Description: [PROJECT_DESCRIPTION]</p>' +
                    '<p>Decision: [DECISION]</p>' +
                    '<p>Comments: [COMMENTS]</p>' +
                    '<p>Supervisor: [SUPERVISOR_NAME]</p>' +
                    '<p>Email: [SUPERVISOR_EMAIL]</p>' +
                    '<p>Phone: [SUPERVISOR_PHONE]</p>' +
                    '</body></html>',
                Body = 'Architecture approval notification.'
            ));
        }

        if (!templatesToCreate.isEmpty()) {
            insert templatesToCreate;
        }

        Set<String> availableNames = new Set<String>();

        for (EmailTemplate availableTemplate : [
            SELECT DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName IN :templateNames
        ]) {
            availableNames.add(availableTemplate.DeveloperName);
        }

        System.assertEquals(
            templateNames,
            availableNames,
            'Each required email template developer name ' +
            'must be available.'
        );
    }

    /**
     * @description Creates a Salesforce File linked to a design.
     * @param designId Architecture Design ID.
     * @return Inserted ContentVersion.
     */
    private static ContentVersion createDesignAttachment(Id designId) {
        ContentVersion fileVersion = new ContentVersion(
            Title = 'Architecture Approval Document',
            PathOnClient = 'ArchitectureApproval.pdf',
            VersionData = Blob.valueOf(
                'Architecture approval test attachment.'
            ),
            FirstPublishLocationId = designId
        );

        insert fileVersion;

        System.assertNotEquals(
            null,
            fileVersion.Id,
            'Architecture attachment must be created.'
        );

        return fileVersion;
    }

    /**
     * @description Verifies client email processing for
     * an approved Arelia Opportunity.
     */
    @IsTest
    static void managerApprovalProcessesClientEmail() {
        createNotificationTemplates();

        Opportunity testOpportunity = createAreliaOpportunity(
            'Architecture Client Email Test'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            false,
            null
        );

        Test.startTest();

        Integer jobsBefore = Limits.getQueueableJobs();
        Integer emailsBefore = Limits.getEmailInvocations();

        testDesign.Manager_Approval__c = true;
        testDesign.Manager_Comments__c =
            'Architecture design approved successfully.';

        update testDesign;

        Integer jobsAfter = Limits.getQueueableJobs();
        Integer emailsAfter = Limits.getEmailInvocations();

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            NO_JOBS,
            'Approval without architect date must not ' +
            'enqueue a mobile push job.'
        );

        System.assert(
            emailsAfter > emailsBefore,
            'Manager approval should invoke email delivery ' +
            'for the configured Arelia Opportunity.'
        );

        Test.stopTest();

        Architecture_Design__c updatedDesign = [
            SELECT Id, Manager_Approval__c,
                   Manager_Comments__c, Opportunity__c
            FROM Architecture_Design__c
            WHERE Id = :testDesign.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            updatedDesign.Manager_Approval__c,
            'Manager approval must be persisted.'
        );

        System.assertEquals(
            'Architecture design approved successfully.',
            updatedDesign.Manager_Comments__c,
            'Manager comments must be preserved.'
        );
    }

    /**
     * @description Verifies email processing when an
     * Architecture Design has an attached file.
     */
    @IsTest
    static void managerApprovalWithAttachmentProcessesEmails() {
        createNotificationTemplates();

        Opportunity testOpportunity = createAreliaOpportunity(
            'Architecture Attachment Email Test'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            false,
            null
        );

        createDesignAttachment(testDesign.Id);

        List<ContentDocumentLink> fileLinks = [
            SELECT Id, ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testDesign.Id
        ];

        System.assert(
            !fileLinks.isEmpty(),
            'Architecture Design must have an attached file.'
        );

        Test.startTest();
        Integer emailsBefore = Limits.getEmailInvocations();

        testDesign.Manager_Approval__c = true;
        testDesign.Manager_Comments__c =
            'Approved with architecture document.';

        update testDesign;

        Integer emailsAfter = Limits.getEmailInvocations();

        System.assert(
            emailsAfter > emailsBefore,
            'Approval with an attachment should invoke ' +
            'email processing.'
        );

        Test.stopTest();

        Architecture_Design__c updatedDesign = [
            SELECT Id, Manager_Approval__c
            FROM Architecture_Design__c
            WHERE Id = :testDesign.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            updatedDesign.Manager_Approval__c,
            'Manager approval must remain true.'
        );
    }

    /**
     * @description Verifies client and supervisor recipients
     * are configured for email processing.
     */
    @IsTest
    static void managerApprovalWithBothRecipients() {
        createNotificationTemplates();

        Opportunity testOpportunity = createAreliaOpportunity(
            'Client Supervisor Email Test'
        );

        Opportunity configuredOpportunity = [
            SELECT Id, RecordTypeId,
                   Primary_Contact__r.Email,
                   Supervisor_User_Email__c
            FROM Opportunity
            WHERE Id = :testOpportunity.Id
            LIMIT 1
        ];

        System.assertNotEquals(
            null,
            configuredOpportunity.Primary_Contact__r,
            'Primary client contact must exist.'
        );

        System.assert(
            String.isNotBlank(
                configuredOpportunity.Primary_Contact__r.Email
            ),
            'Client email must be configured.'
        );

        System.assert(
            String.isNotBlank(
                configuredOpportunity.Supervisor_User_Email__c
            ),
            'Supervisor email must be configured.'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            false,
            null
        );

        Test.startTest();
        Integer emailsBefore = Limits.getEmailInvocations();

        testDesign.Manager_Approval__c = true;
        update testDesign;

        Integer emailsAfter = Limits.getEmailInvocations();

        System.assert(
            emailsAfter > emailsBefore,
            'Client and supervisor approval notifications ' +
            'must invoke email processing.'
        );

        Test.stopTest();
    }

    /**
     * @description Verifies manager approval persists
     * independently of org email-template visibility.
     */
    @IsTest
    static void approvalWithoutTemplatesPersistsDecision() {
        Opportunity testOpportunity = createAreliaOpportunity(
            'Template Independent Approval Test'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            false,
            null
        );

        Test.startTest();
        Integer jobsBefore = Limits.getQueueableJobs();

        testDesign.Manager_Approval__c = true;
        update testDesign;

        Integer jobsAfter = Limits.getQueueableJobs();
        Test.stopTest();

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            NO_JOBS,
            'Approval without architect date must not enqueue push.'
        );

        Architecture_Design__c savedDesign = [
            SELECT Manager_Approval__c, Opportunity__c
            FROM Architecture_Design__c
            WHERE Id = :testDesign.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            savedDesign.Manager_Approval__c,
            'Manager approval must persist regardless of templates.'
        );

        System.assertEquals(
            testOpportunity.Id,
            savedDesign.Opportunity__c,
            'Related Opportunity must remain unchanged.'
        );
    }

    /**
     * @description Verifies supervisor email processing
     * when the primary client Contact has no email.
     */
    @IsTest
    static void approvalWithSupervisorOnlyProcessesEmail() {
        createNotificationTemplates();

        Opportunity testOpportunity = createAreliaOpportunity(
            'Supervisor Only Email Test'
        );

        Contact contactWithoutEmail = new Contact(
            LastName = 'Contact Without Email'
        );
        insert contactWithoutEmail;

        testOpportunity.Primary_Contact__c = contactWithoutEmail.Id;
        update testOpportunity;

        Opportunity configuredOpportunity = [
            SELECT Supervisor_User_Email__c,
                   Primary_Contact__r.Email
            FROM Opportunity
            WHERE Id = :testOpportunity.Id
            LIMIT 1
        ];

        System.assertEquals(
            null,
            configuredOpportunity.Primary_Contact__r.Email,
            'Client email must be absent in this scenario.'
        );

        System.assert(
            String.isNotBlank(
                configuredOpportunity.Supervisor_User_Email__c
            ),
            'Supervisor email must be available.'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            false,
            null
        );

        Test.startTest();
        Integer emailsBefore = Limits.getEmailInvocations();

        testDesign.Manager_Approval__c = true;
        update testDesign;

        Integer emailsAfter = Limits.getEmailInvocations();
        Test.stopTest();

        System.assert(
            emailsAfter > emailsBefore,
            'Supervisor should receive email without a client address.'
        );
    }

    /**
     * @description Verifies multiple approvals are
     * processed in a single email trigger execution.
     */
    @IsTest
    static void bulkApprovalsProcessEmailBatch() {
        createNotificationTemplates();

        Opportunity testOpportunity = createAreliaOpportunity(
            'Bulk Email Batch Test'
        );

        List<Architecture_Design__c> designs =
            new List<Architecture_Design__c>();

        for (
            Integer index = 0;
            index < BULK_RECORD_COUNT;
            index++
        ) {
            designs.add(new Architecture_Design__c(
                Opportunity__c = testOpportunity.Id,
                Manager_Approval__c = false,
                Architect_Approved_Date__c = null
            ));
        }

        insert designs;

        for (Architecture_Design__c design : designs) {
            design.Manager_Approval__c = true;
        }

        Test.startTest();

        Integer emailsBefore = Limits.getEmailInvocations();
        Integer jobsBefore = Limits.getQueueableJobs();

        update designs;

        Integer emailsAfter = Limits.getEmailInvocations();
        Integer jobsAfter = Limits.getQueueableJobs();

        Test.stopTest();

        System.assert(
            emailsAfter > emailsBefore,
            'Bulk approvals should invoke email processing.'
        );

        assertQueueableJobs(
            jobsBefore,
            jobsAfter,
            NO_JOBS,
            'Bulk approvals without dates must not enqueue push.'
        );
    }

    /**
     * @description Verifies email processing when multiple
     * Salesforce Files are linked to the design.
     */
    @IsTest
    static void managerApprovalWithMultipleFilesProcessesEmail() {
        createNotificationTemplates();

        Opportunity testOpportunity = createAreliaOpportunity(
            'Multiple Architecture Files Test'
        );

        Architecture_Design__c testDesign = createDesign(
            testOpportunity.Id,
            false,
            null
        );

        createDesignAttachment(testDesign.Id);

        ContentVersion secondFile = new ContentVersion(
            Title = 'Architecture Secondary Document',
            PathOnClient = 'ArchitectureSecondary.txt',
            VersionData = Blob.valueOf(
                'Secondary architecture design file.'
            ),
            FirstPublishLocationId = testDesign.Id
        );
        insert secondFile;

        Integer filesLinked = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :testDesign.Id
        ];

        System.assertEquals(
            2,
            filesLinked,
            'Two documents should be linked to the design.'
        );

        Test.startTest();
        Integer emailsBefore = Limits.getEmailInvocations();

        testDesign.Manager_Approval__c = true;
        update testDesign;

        Integer emailsAfter = Limits.getEmailInvocations();

        Test.stopTest();

        System.assert(
            emailsAfter > emailsBefore,
            'Approval with multiple attachments must invoke email.'
        );
    }
}