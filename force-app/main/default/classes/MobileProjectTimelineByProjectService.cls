@RestResource(urlMapping='/mobileProjectTimelineByProject')
global without sharing class MobileProjectTimelineByProjectService {

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

    /* ===================== RESPONSE ===================== */
    global class TimelineResponse {
        public Boolean success;
        public String message;
        public List<TimelineDTO> timelines;
    }

    @HttpPost
    global static TimelineResponse getTimeline() {

        TimelineResponse res = new TimelineResponse();
        res.success = false;
        res.timelines = new List<TimelineDTO>();

        try {
            // ---------- SAFE REQUEST ----------
            String raw = (RestContext.request.requestBody == null)
                ? null
                : RestContext.request.requestBody.toString();

            if (String.isBlank(raw)) {
                res.message = 'Request body is empty';
                return res;
            }

            Map<String, Object> input =
                (Map<String, Object>) JSON.deserializeUntyped(raw);

            String projectId = (String) input.get('projectId');

            if (String.isBlank(projectId)) {
                res.message = 'ProjectId is required';
                return res;
            }

            // ---------- SAFE PROJECT QUERY ----------
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
                       Project_Timeline_Status__c
                FROM Project__c
                WHERE Id = :projectId
                LIMIT 1
            ];

            if (projects.isEmpty()) {
                res.message = 'Project not found';
                return res;
            }

            Project__c p = projects[0];

            // ---------- MAP TO TIMELINE DTO ----------
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

            res.timelines.add(dto);

            res.success = true;
            res.message = 'Success';
            return res;

        } catch (Exception e) {
            res.success = false;
            res.message = e.getMessage();
            return res;
        }
    }
}