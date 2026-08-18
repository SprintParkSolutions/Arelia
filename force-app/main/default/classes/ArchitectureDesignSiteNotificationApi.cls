/**
 * Customer-site API for Architecture Design notifications and decisions.
 *
 * The contactId is treated as an ownership assertion, not as authentication:
 * every request verifies that the contact is the Opportunity primary contact
 * or that the contact email matches the Opportunity customer email used by
 * the existing email notification flow.
 * Updating Status__c intentionally invokes ArchitectureDesignTrigger, which
 * keeps email and site decisions on the same notification workflow.
 */
@RestResource(urlMapping='/registration/opportunity/design-notification-approvals/*')
global without sharing class ArchitectureDesignSiteNotificationApi {
    private static final String STATUS_SENT = 'Sent';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_CHANGES = 'Changes Requested';

    global class DecisionRequest {
        public Id opportunityId;
        public Id contactId;
        public Id designId;
        public String status;
        public String comments;
    }

    @HttpGet
    global static void getApprovals() {
        RestRequest request = RestContext.request;
        Id contactId = parseId(request.params.get('contactId'));
        Id opportunityId = parseId(request.params.get('opportunityId'));
        Id designId = parseId(request.params.get('designId'));
        Id versionId = parseId(request.params.get('versionId'));

        if (contactId == null) {
            writeError(400, 'contactId is required.');
            return;
        }

        if (request.requestURI.endsWith('/file')) {
            serveFile(contactId, opportunityId, designId, versionId);
            return;
        }

        List<Opportunity> ownedOpportunities = getAuthorizedOpportunities(contactId, opportunityId);
        Set<Id> opportunityIds = new Map<Id, Opportunity>(ownedOpportunities).keySet();
        Map<Id, String> opportunityNames = new Map<Id, String>();
        for (Opportunity opportunity : ownedOpportunities) {
            opportunityNames.put(opportunity.Id, opportunity.Name);
        }

        List<Architecture_Design__c> designs = opportunityIds.isEmpty()
            ? new List<Architecture_Design__c>()
            : [SELECT Id, Name, Opportunity__c, Status__c, Comments__c, CreatedDate
               FROM Architecture_Design__c
               WHERE Opportunity__c IN :opportunityIds
               ORDER BY CreatedDate DESC];

        Map<Id, List<Object>> filesByDesign = buildFilesByDesign(new Map<Id, Architecture_Design__c>(designs).keySet());
        List<Object> items = new List<Object>();
        for (Architecture_Design__c design : designs) {
            Boolean pending = design.Status__c == STATUS_SENT;
            items.add(new Map<String, Object>{
                'designId' => design.Id,
                'designName' => design.Name,
                'opportunityId' => design.Opportunity__c,
                'opportunityName' => opportunityNames.get(design.Opportunity__c),
                'status' => design.Status__c,
                'comments' => design.Comments__c,
                'createdDate' => design.CreatedDate,
                'canApprove' => pending,
                'canRequestChanges' => pending,
                'files' => filesByDesign.containsKey(design.Id) ? filesByDesign.get(design.Id) : new List<Object>()
            });
        }

        writeJson(200, new Map<String, Object>{
            'success' => true,
            'data' => new Map<String, Object>{ 'designs' => items }
        });
    }

    @HttpPost
    global static void submitDecision() {
        DecisionRequest input;
        try {
            input = (DecisionRequest) JSON.deserialize(RestContext.request.requestBody.toString(), DecisionRequest.class);
        } catch (Exception ignored) {
            writeError(400, 'Invalid request body.');
            return;
        }

        if (input == null || input.contactId == null || input.opportunityId == null || input.designId == null) {
            writeError(400, 'contactId, opportunityId, and designId are required.');
            return;
        }
        if (input.status != STATUS_APPROVED && input.status != STATUS_CHANGES) {
            writeError(400, 'Status must be Approved or Changes Requested.');
            return;
        }
        String comments = String.isBlank(input.comments) ? null : input.comments.trim();
        if (input.status == STATUS_CHANGES && String.isBlank(comments)) {
            writeError(400, 'Comments are required when requesting changes.');
            return;
        }

        Set<Id> authorizedOpportunityIds = new Map<Id, Opportunity>(
            getAuthorizedOpportunities(input.contactId, input.opportunityId)
        ).keySet();
        if (!authorizedOpportunityIds.contains(input.opportunityId)) {
            writeError(404, 'Architecture Design not found.');
            return;
        }

        List<Architecture_Design__c> matches = [
            SELECT Id, Status__c
            FROM Architecture_Design__c
            WHERE Id = :input.designId
            AND Opportunity__c = :input.opportunityId
            LIMIT 1
        ];
        if (matches.isEmpty()) {
            writeError(404, 'Architecture Design not found.');
            return;
        }
        if (matches[0].Status__c != STATUS_SENT) {
            writeError(409, 'A decision has already been submitted for this design.');
            return;
        }

        matches[0].Status__c = input.status;
        matches[0].Comments__c = input.status == STATUS_APPROVED && String.isBlank(comments)
            ? 'Approved By Client'
            : comments;
        try {
            Database.SaveResult saveResult = Database.update(matches[0], AccessLevel.SYSTEM_MODE);
            if (!saveResult.isSuccess()) {
                String message = saveResult.getErrors().isEmpty()
                    ? 'Unable to submit the design decision.'
                    : saveResult.getErrors()[0].getMessage();
                writeError(400, message);
                return;
            }
        } catch (Exception error) {
            writeError(400, error.getMessage());
            return;
        }

        writeJson(200, new Map<String, Object>{
            'success' => true,
            'message' => input.status == STATUS_APPROVED
                ? 'Design approved successfully.'
                : 'Change request submitted successfully.'
        });
    }

    private static void serveFile(Id contactId, Id opportunityId, Id designId, Id versionId) {
        if (opportunityId == null || designId == null || versionId == null) {
            writeError(400, 'opportunityId, designId, and versionId are required.');
            return;
        }
        Set<Id> authorizedOpportunityIds = new Map<Id, Opportunity>(
            getAuthorizedOpportunities(contactId, opportunityId)
        ).keySet();
        if (!authorizedOpportunityIds.contains(opportunityId)) {
            writeError(404, 'Design file not found.');
            return;
        }
        List<Architecture_Design__c> authorizedDesigns = [
            SELECT Id FROM Architecture_Design__c
            WHERE Id = :designId AND Opportunity__c = :opportunityId
            LIMIT 1
        ];
        if (authorizedDesigns.isEmpty()) {
            writeError(404, 'Design file not found.');
            return;
        }
        Set<Id> linkedDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId = :designId
        ]) {
            linkedDocumentIds.add(link.ContentDocumentId);
        }
        List<ContentVersion> versions = linkedDocumentIds.isEmpty()
            ? new List<ContentVersion>()
            : [
            SELECT Title, FileExtension, VersionData
            FROM ContentVersion
            WHERE Id = :versionId
            AND ContentDocumentId IN :linkedDocumentIds
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            writeError(404, 'Design file not found.');
            return;
        }
        ContentVersion version = versions[0];
        RestContext.response.statusCode = 200;
        RestContext.response.addHeader('Content-Type', contentType(version.FileExtension));
        RestContext.response.addHeader('Content-Disposition', 'inline; filename="' + safeFileName(version.Title, version.FileExtension) + '"');
        RestContext.response.responseBody = version.VersionData;
    }

    private static Map<Id, List<Object>> buildFilesByDesign(Set<Id> designIds) {
        Map<Id, List<Object>> result = new Map<Id, List<Object>>();
        if (designIds.isEmpty()) return result;
        List<ContentDocumentLink> links = [
            SELECT LinkedEntityId, ContentDocument.LatestPublishedVersionId,
                   ContentDocument.Title, ContentDocument.FileExtension
            FROM ContentDocumentLink WHERE LinkedEntityId IN :designIds
        ];
        for (ContentDocumentLink link : links) {
            if (!result.containsKey(link.LinkedEntityId)) result.put(link.LinkedEntityId, new List<Object>());
            result.get(link.LinkedEntityId).add(new Map<String, Object>{
                'versionId' => link.ContentDocument.LatestPublishedVersionId,
                'title' => link.ContentDocument.Title,
                'extension' => link.ContentDocument.FileExtension,
                'contentType' => contentType(link.ContentDocument.FileExtension)
            });
        }
        return result;
    }

    private static List<Opportunity> getAuthorizedOpportunities(Id contactId, Id opportunityId) {
        List<Contact> contacts = [
            SELECT Id, Email FROM Contact WHERE Id = :contactId LIMIT 1
        ];
        if (contacts.isEmpty()) return new List<Opportunity>();

        String customerEmail = contacts[0].Email;
        if (opportunityId == null) {
            return String.isBlank(customerEmail)
                ? [SELECT Id, Name FROM Opportunity WHERE Primary_Contact__c = :contactId]
                : [SELECT Id, Name FROM Opportunity
                   WHERE Primary_Contact__c = :contactId OR Email__c = :customerEmail];
        }
        return String.isBlank(customerEmail)
            ? [SELECT Id, Name FROM Opportunity
               WHERE Id = :opportunityId AND Primary_Contact__c = :contactId]
            : [SELECT Id, Name FROM Opportunity
               WHERE Id = :opportunityId
               AND (Primary_Contact__c = :contactId OR Email__c = :customerEmail)];
    }

    private static Id parseId(String value) {
        if (String.isBlank(value)) return null;
        try { return (Id) value; } catch (Exception ignored) { return null; }
    }

    private static String contentType(String extension) {
        String ext = String.isBlank(extension) ? '' : extension.toLowerCase();
        if (ext == 'png') return 'image/png';
        if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
        if (ext == 'gif') return 'image/gif';
        if (ext == 'webp') return 'image/webp';
        if (ext == 'pdf') return 'application/pdf';
        if (ext == 'zip') return 'application/zip';
        return 'application/octet-stream';
    }

    private static String safeFileName(String title, String extension) {
        String name = String.isBlank(title) ? 'design-file' : title.replaceAll('[\\r\\n\\"]', '_');
        return String.isBlank(extension) ? name : name + '.' + extension;
    }

    private static void writeError(Integer statusCode, String message) {
        writeJson(statusCode, new Map<String, Object>{ 'success' => false, 'message' => message });
    }

    private static void writeJson(Integer statusCode, Object body) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(body));
    }
}
