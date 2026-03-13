@RestResource(urlMapping='/mobile/project-files')
global without sharing class MobileProjectFilesService {

    global class FileDTO {
        public String documentId;
        public String versionId;
        public String title;
        public String fileType;
        public Integer fileSize;
        public String downloadUrl;
        public String previewUrl;
    }

    @HttpPost
    global static List<FileDTO> getProjectFiles() {

        String rawBody = RestContext.request.requestBody == null
            ? null
            : RestContext.request.requestBody.toString();

        Map<String, Object> input =
            (rawBody == null || rawBody.trim() == '')
            ? new Map<String, Object>()
            : (Map<String, Object>) JSON.deserializeUntyped(rawBody);

        String projectId = (String) input.get('projectId');

        if (String.isBlank(projectId)) {
            return new List<FileDTO>();
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.FileType,
                   ContentDocument.ContentSize,
                   ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :projectId
            ORDER BY ContentDocument.CreatedDate DESC
        ];

        String baseUrl = URL.getOrgDomainUrl().toExternalForm();

        List<FileDTO> result = new List<FileDTO>();

        for (ContentDocumentLink link : links) {
            FileDTO dto = new FileDTO();
            dto.documentId = link.ContentDocumentId;
            dto.versionId = link.ContentDocument.LatestPublishedVersionId;
            dto.title = link.ContentDocument.Title;
            dto.fileType = link.ContentDocument.FileType;
            dto.fileSize = link.ContentDocument.ContentSize;

            dto.downloadUrl =
                baseUrl + '/sfc/servlet.shepherd/version/download/' +
                dto.versionId;

            dto.previewUrl =
                baseUrl + '/sfc/servlet.shepherd/version/renditionDownload' +
                '?rendition=THUMB720BY512&versionId=' +
                dto.versionId;

            result.add(dto);
        }

        return result;
    }
}