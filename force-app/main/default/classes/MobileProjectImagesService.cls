@RestResource(urlMapping='/mobileProjectImages')
global without sharing class MobileProjectImagesService {

    global class ImageDTO {
        public String documentId;
        public String versionId;
        public String title;
        public String imageUrl;
    }

    global class ResponseDTO {
        public Boolean success;
        public String message;
        public List<ImageDTO> images;
    }

    @HttpPost
    global static ResponseDTO getProjectImages() {

        ResponseDTO resp = new ResponseDTO();
        resp.success = false;
        resp.images = new List<ImageDTO>();

        try {
            String raw = RestContext.request.requestBody == null
                ? null
                : RestContext.request.requestBody.toString();

            Map<String, Object> input =
                (raw == null || raw.trim() == '')
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(raw);

            String projectId = (String) input.get('projectId');
            if (String.isBlank(projectId)) {
                resp.message = 'Missing Project Id';
                return resp;
            }

            // 🔹 Fetch only IMAGE files linked to Project
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId,
                       ContentDocument.Title,
                       ContentDocument.FileType,
                       ContentDocument.LatestPublishedVersionId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :projectId
                AND ContentDocument.FileType IN ('PNG', 'JPG', 'JPEG')
                ORDER BY ContentDocument.CreatedDate DESC
            ];

            String baseUrl = URL.getOrgDomainUrl().toExternalForm();

            for (ContentDocumentLink cdl : links) {
                ImageDTO img = new ImageDTO();
                img.documentId = cdl.ContentDocumentId;
                img.versionId = cdl.ContentDocument.LatestPublishedVersionId;
                img.title = cdl.ContentDocument.Title;

                // 🔥 Direct image load URL (best for Android)
                img.imageUrl =
                    baseUrl +
                    '/sfc/servlet.shepherd/version/download/' +
                    img.versionId;

                resp.images.add(img);
            }

            resp.success = true;
            resp.message = 'Success';
            return resp;

        } catch (Exception e) {
            resp.success = false;
            resp.message = e.getMessage();
            return resp;
        }
    }
}