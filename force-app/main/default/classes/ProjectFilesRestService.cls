@RestResource(urlMapping='/mobile/projectfiles')
global without sharing class ProjectFilesRestService {

    global class FileDTO {
        public String fileId;
        public String title;
        public String fileType;
        public String downloadUrl;
    }

    @HttpPost
    global static List<FileDTO> getProjectFiles() {

        String raw = RestContext.request.requestBody == null
            ? null
            : RestContext.request.requestBody.toString();

        Map<String, Object> input =
            (raw == null || raw.trim() == '')
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(raw);

        String projectId = (String) input.get('projectId');
        if (String.isBlank(projectId)) {
            return new List<FileDTO>();
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :projectId
        ];

        if (links.isEmpty()) return new List<FileDTO>();

        Set<Id> docIds = new Set<Id>();
        for (ContentDocumentLink l : links) {
            docIds.add(l.ContentDocumentId);
        }

        List<ContentVersion> versions = [
            SELECT Id, Title, FileType
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
            AND IsLatest = true
        ];

        // ✅ EXPERIENCE CLOUD BASE URL (STRING)
        String siteBaseUrl = Site.getBaseUrl();
        
        List<FileDTO> result = new List<FileDTO>();
        for (ContentVersion v : versions) {

            FileDTO dto = new FileDTO();
            dto.fileId = v.Id;
            dto.title = v.Title;
            dto.fileType = v.FileType;

            // ✅ GUEST-ACCESSIBLE URL
      dto.downloadUrl =
                siteBaseUrl
                + '/sfc/servlet.shepherd/version/download/'
                + v.Id;



            result.add(dto);
        }

        return result;
    }
}