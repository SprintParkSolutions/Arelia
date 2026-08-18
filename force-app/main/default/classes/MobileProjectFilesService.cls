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

    global class ResponseDTO {
        public Boolean success;
        public String message;
        public String projectId;
        public Integer totalCount;
        public List<FileDTO> files;
    }

    @HttpPost
    global static ResponseDTO getProjectFiles() {
        ResponseDTO resp = new ResponseDTO();
        resp.success = false;
        resp.files = new List<FileDTO>();
        resp.totalCount = 0;

        try {
            String rawBody = RestContext.request.requestBody == null
                ? null
                : RestContext.request.requestBody.toString();

            Map<String, Object> input =
                String.isBlank(rawBody)
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(rawBody);

            String projectId = (String) input.get('projectId');
            resp.projectId = projectId;

            if (String.isBlank(projectId)) {
                resp.message = 'Missing Project Id';
                return resp;
            }

            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId,
                       ContentDocument.Title,
                       ContentDocument.FileType,
                       ContentDocument.ContentSize,
                       ContentDocument.LatestPublishedVersionId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :projectId
                  AND ContentDocument.LatestPublishedVersionId != null
                ORDER BY ContentDocument.CreatedDate DESC
            ];

            for (ContentDocumentLink link : links) {
                FileDTO dto = new FileDTO();
                dto.documentId = link.ContentDocumentId;
                dto.versionId = link.ContentDocument.LatestPublishedVersionId;
                dto.title = link.ContentDocument.Title;
                dto.fileType = link.ContentDocument.FileType;
                dto.fileSize = link.ContentDocument.ContentSize == null
                    ? null
                    : Integer.valueOf(link.ContentDocument.ContentSize);
                dto.downloadUrl = '/sfc/servlet.shepherd/version/download/' + dto.versionId;
                dto.previewUrl =
                    '/sfc/servlet.shepherd/version/renditionDownload' +
                    '?rendition=THUMB720BY512&versionId=' + dto.versionId;
                resp.files.add(dto);
            }

            resp.success = true;
            resp.totalCount = resp.files.size();
            resp.message = resp.totalCount > 0
                ? 'Success'
                : 'No files found for this project.';
            return resp;
        } catch (Exception e) {
            resp.success = false;
            resp.message = e.getMessage();
            return resp;
        }
    }
}