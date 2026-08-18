@RestResource(urlMapping='/registration/opportunity/design-approvals/*')
global without sharing class DesignApprovalRestResponseController {
    private static final String APPROVED = 'Approved';
    private static final String CHANGES = 'Changes Requested';

    global class ApiResponse {
        global Boolean success;
        global String message;
        global Object data;

        global ApiResponse(Boolean success, String message, Object data) {
            this.success = success;
            this.message = message;
            this.data = data;
        }
    }

    global class ListResponse {
        global Id contactId;
        global List<DesignData> designs = new List<DesignData>();
    }

    global class DesignData {
        global Id opportunityId;
        global String opportunityName;
        global Id designId;
        global String designName;
        global String status;
        global String comments;
        global Decimal architectureBudget;
        global Datetime createdDate;
        global Boolean canApprove;
        global Boolean canRequestChanges;
        global List<FileData> files = new List<FileData>();
    }

    global class FileData {
        global Id versionId;
        global String title;
        global String extension;
        global String contentType;
        global Long size;
    }

    global class DecisionRequest {
        global String contactId;
        global String opportunityId;
        global String designId;
        global String status;
        global String comments;
    }

    global class DecisionResponse {
        global Id opportunityId;
        global Id designId;
        global String status;
        global String comments;
        global Boolean decisionSubmitted;
    }

    @HttpGet
    global static void doGet() {
        try {
            String uri = RestContext.request.requestURI == null ? '' : RestContext.request.requestURI.toLowerCase();
            if (uri.endsWith('/file')) {
                serveFile();
            } else {
                listDesigns();
            }
        } catch (Exception error) {
            writeError(error);
        }
    }

    @HttpPost
    global static void doPost() {
        try {
            DecisionRequest input = (DecisionRequest)JSON.deserialize(
                RestContext.request.requestBody == null ? '' : RestContext.request.requestBody.toString(),
                DecisionRequest.class
            );
            if (input == null) fail('Request body is required.');

            Id contactId = typedId(input.contactId, Contact.SObjectType, 'Invalid Contact ID.');
            Id opportunityId = typedId(input.opportunityId, Opportunity.SObjectType, 'Invalid Opportunity ID.');
            Id designId = typedId(input.designId, Architecture_Design__c.SObjectType, 'Invalid Architecture Design ID.');

            assertOpportunityAccess(contactId, opportunityId);

            List<Architecture_Design__c> rows = [
                SELECT Id, Status__c, Comments__c
                FROM Architecture_Design__c
                WHERE Id = :designId AND Opportunity__c = :opportunityId
                LIMIT 1
            ];
            if (rows.isEmpty()) notFound('Architecture Design not found.');

            Architecture_Design__c design = rows[0];
            if (design.Status__c == APPROVED || design.Status__c == CHANGES) {
                conflict('A decision has already been submitted.');
            }
            if (input.status != APPROVED && input.status != CHANGES) {
                fail('status must be Approved or Changes Requested.');
            }
            if (input.status == CHANGES && String.isBlank(input.comments)) {
                fail('Comments are required when requesting changes.');
            }

            design.Status__c = input.status;
            design.Comments__c = String.isBlank(input.comments) ? 'Approved By Client' : input.comments.trim();
            Database.SaveResult saveResult = Database.update(design, AccessLevel.SYSTEM_MODE);
            if (!saveResult.isSuccess()) {
                String message = saveResult.getErrors().isEmpty()
                    ? 'Unable to submit the design decision.'
                    : saveResult.getErrors()[0].getMessage();
                fail(message);
            }

            DecisionResponse result = new DecisionResponse();
            result.opportunityId = opportunityId;
            result.designId = design.Id;
            result.status = design.Status__c;
            result.comments = design.Comments__c;
            result.decisionSubmitted = true;
            writeJson(200, new ApiResponse(true, 'Design decision submitted successfully.', result));
        } catch (Exception error) {
            writeError(error);
        }
    }

    private static void listDesigns() {
        Id contactId = typedId(RestContext.request.params.get('contactId'), Contact.SObjectType, 'Invalid Contact ID.');
        String requestedOpportunity = RestContext.request.params.get('opportunityId');

        List<Opportunity> opportunities;
        if (String.isBlank(requestedOpportunity)) {
            opportunities = [
                SELECT Id, Name
                FROM Opportunity
                WHERE Primary_Contact__c = :contactId
                ORDER BY CreatedDate DESC
            ];
        } else {
            Id opportunityId = typedId(requestedOpportunity, Opportunity.SObjectType, 'Invalid Opportunity ID.');
            opportunities = [
                SELECT Id, Name
                FROM Opportunity
                WHERE Id = :opportunityId AND Primary_Contact__c = :contactId
            ];
        }

        Map<Id, Opportunity> opportunityMap = new Map<Id, Opportunity>(opportunities);
        Set<Id> opportunityIds = opportunityMap.keySet();
        List<Architecture_Design__c> designs = opportunityIds.isEmpty()
            ? new List<Architecture_Design__c>()
            : [
                SELECT Id, Name, Status__c, Comments__c, Architecture_Budget__c, CreatedDate, Opportunity__c
                FROM Architecture_Design__c
                WHERE Opportunity__c IN :opportunityIds
                ORDER BY CreatedDate DESC
            ];

        Set<Id> designIds = new Map<Id, Architecture_Design__c>(designs).keySet();
        Map<Id, List<Id>> docsByDesign = new Map<Id, List<Id>>();
        Set<Id> documentIds = new Set<Id>();
        if (!designIds.isEmpty()) {
            for (ContentDocumentLink link : [
                SELECT LinkedEntityId, ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :designIds
            ]) {
                if (!docsByDesign.containsKey(link.LinkedEntityId)) {
                    docsByDesign.put(link.LinkedEntityId, new List<Id>());
                }
                docsByDesign.get(link.LinkedEntityId).add(link.ContentDocumentId);
                documentIds.add(link.ContentDocumentId);
            }
        }

        Map<Id, ContentVersion> versionsByDocument = new Map<Id, ContentVersion>();
        if (!documentIds.isEmpty()) {
            for (ContentVersion version : [
                SELECT Id, ContentDocumentId, Title, FileExtension, ContentSize
                FROM ContentVersion
                WHERE ContentDocumentId IN :documentIds AND IsLatest = true
            ]) {
                versionsByDocument.put(version.ContentDocumentId, version);
            }
        }

        ListResponse result = new ListResponse();
        result.contactId = contactId;
        for (Architecture_Design__c design : designs) {
            DesignData item = new DesignData();
            item.opportunityId = design.Opportunity__c;
            item.opportunityName = opportunityMap.get(design.Opportunity__c).Name;
            item.designId = design.Id;
            item.designName = design.Name;
            item.status = design.Status__c;
            item.comments = design.Comments__c;
            item.architectureBudget = design.Architecture_Budget__c;
            item.createdDate = design.CreatedDate;
            item.canApprove = design.Status__c != APPROVED && design.Status__c != CHANGES;
            item.canRequestChanges = item.canApprove;

            for (Id documentId : docsByDesign.containsKey(design.Id) ? docsByDesign.get(design.Id) : new List<Id>()) {
                ContentVersion version = versionsByDocument.get(documentId);
                if (version == null) continue;

                FileData file = new FileData();
                file.versionId = version.Id;
                file.title = version.Title;
                file.extension = version.FileExtension;
                file.contentType = contentType(version.FileExtension);
                file.size = version.ContentSize;
                item.files.add(file);
            }
            result.designs.add(item);
        }

        writeJson(200, new ApiResponse(true, 'Architecture designs retrieved successfully.', result));
    }

    private static void serveFile() {
        Id contactId = typedId(RestContext.request.params.get('contactId'), Contact.SObjectType, 'Invalid Contact ID.');
        Id opportunityId = typedId(RestContext.request.params.get('opportunityId'), Opportunity.SObjectType, 'Invalid Opportunity ID.');
        Id designId = typedId(RestContext.request.params.get('designId'), Architecture_Design__c.SObjectType, 'Invalid Architecture Design ID.');
        Id versionId = typedId(RestContext.request.params.get('versionId'), ContentVersion.SObjectType, 'Invalid Content Version ID.');

        assertOpportunityAccess(contactId, opportunityId);

        List<Architecture_Design__c> designs = [
            SELECT Id
            FROM Architecture_Design__c
            WHERE Id = :designId AND Opportunity__c = :opportunityId
            LIMIT 1
        ];
        if (designs.isEmpty()) notFound('Architecture Design not found.');

        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, Title, FileExtension, VersionData
            FROM ContentVersion
            WHERE Id = :versionId
            LIMIT 1
        ];
        if (versions.isEmpty()) notFound('File not found.');

        Integer links = [
            SELECT count()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :designId AND ContentDocumentId = :versions[0].ContentDocumentId
        ];
        if (links == 0) forbidden('You are not authorized to access this file.');

        RestContext.response.statusCode = 200;
        RestContext.response.addHeader('Content-Type', contentType(versions[0].FileExtension));
        RestContext.response.addHeader('Content-Disposition', 'inline; filename="' + versions[0].Title.replace('"', '') + '"');
        RestContext.response.addHeader('X-Content-Type-Options', 'nosniff');
        RestContext.response.responseBody = versions[0].VersionData;
    }

    private static void assertOpportunityAccess(Id contactId, Id opportunityId) {
        if ([SELECT count() FROM Opportunity WHERE Id = :opportunityId AND Primary_Contact__c = :contactId] == 0) {
            forbidden('You are not authorized to access this Opportunity.');
        }
    }

    private static Id typedId(String value, Schema.SObjectType expected, String message) {
        try {
            Id result = (Id)value;
            if (result.getSObjectType() != expected) fail(message);
            return result;
        } catch (Exception ignored) {
            fail(message);
            return null;
        }
    }

    private static String contentType(String extension) {
        String ext = String.isBlank(extension) ? '' : extension.toLowerCase();
        if (ext == 'png') return 'image/png';
        if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
        if (ext == 'gif') return 'image/gif';
        if (ext == 'webp') return 'image/webp';
        if (ext == 'pdf') return 'application/pdf';
        return 'application/octet-stream';
    }

    private static void writeJson(Integer status, Object body) {
        RestContext.response.statusCode = status;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(body));
    }

    private static void writeError(Exception error) {
        Integer status = error instanceof ForbiddenException ? 403
            : error instanceof NotFoundException ? 404
            : error instanceof ConflictException ? 409
            : 400;
        writeJson(status, new ApiResponse(false, error.getMessage(), null));
    }

    private static void fail(String message) { throw new ValidationException(message); }
    private static void forbidden(String message) { throw new ForbiddenException(message); }
    private static void notFound(String message) { throw new NotFoundException(message); }
    private static void conflict(String message) { throw new ConflictException(message); }

    private class ValidationException extends Exception {}
    private class ForbiddenException extends Exception {}
    private class NotFoundException extends Exception {}
    private class ConflictException extends Exception {}
}
