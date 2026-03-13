@RestResource(urlMapping='/mobileProjectTimeline')
global without sharing class MobileProjectTimelineService {

    /* ===================== TIMELINE DTO ===================== */
    global class TimelineDTO {
        public String projectId;
        public String projectName;

        public Date   projectStartDate;
        public String estimatedProjectDuration;
        public Date   estimatedEndDate;
        public Date   actualCompletionDate;

        public String projectStatus;
        public String holdReason;
        public Decimal projectDuration;
        public String projectTimelineStatus;
    }

    /* ===================== RESPONSE DTO ===================== */
    global class ResponseDTO {
        public Boolean success;
        public String  message;
        public List<TimelineDTO> timelines;
    }

    /* ===================== API METHOD ===================== */
    @HttpPost
    global static ResponseDTO getProjectTimeline() {

        ResponseDTO resp = new ResponseDTO();
        resp.success = false;
        resp.timelines = new List<TimelineDTO>();

        try {
            String raw = RestContext.request.requestBody == null
                ? null
                : RestContext.request.requestBody.toString();

            Map<String, Object> input = (raw == null || raw.trim() == '')
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(raw);

            String contactId = (String) input.get('contactId');

            if (String.isBlank(contactId)) {
                resp.message = 'Missing Contact Id';
                return resp;
            }

            /* ===================== QUERY PROJECTS ===================== */
            List<Project__c> projects = [
                SELECT Id,
                       Name,
                        Start_Date__c,
                       Estimated_Project_Duration__c,
                       Estimated_End_Date__c,
                        Actual_Completion_Date__c,
                       Status__c,
                       Hold_Reason__c,
                       Project_Duration__c,
                       Project_Timeline_Status__c,
                       Client__c
                FROM Project__c
                WHERE Client__c = :contactId
                ORDER BY Start_Date__c ASC
            ];

            /* ===================== MAP TO DTO ===================== */
            for (Project__c p : projects) {

                TimelineDTO dto = new TimelineDTO();
                dto.projectId = p.Id;
                dto.projectName = p.Name;

                dto.projectStartDate = p.Start_Date__c;
                dto.estimatedProjectDuration = p.Estimated_Project_Duration__c;
                dto.estimatedEndDate = p.Estimated_End_Date__c;
                dto.actualCompletionDate = p.Actual_Completion_Date__c;

                dto.projectStatus = p.Status__c;
                dto.holdReason = p.Hold_Reason__c;
                dto.projectDuration = p.Project_Duration__c;
                dto.projectTimelineStatus = p.Project_Timeline_Status__c;

                resp.timelines.add(dto);
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