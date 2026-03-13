@RestResource(urlMapping='/mobileProjectStatus')
global without sharing class MobileProjectStatusService {

    global class VendorDTO {
        public String  vendorName;
        public String  vendorCategory;
        public Decimal completionPercentage;
        public Date    startDate;
        public Date    endDate;
        public Decimal remainingTasks;
    }

    global class ProjectDTO {
        public String  projectId;
        public String  projectName;
        public String  projectStatus;
        public Decimal budget;
        public Date    startDate;
        public Date    endDate;
        public Decimal completionPercentage;
        public List<VendorDTO> vendors;
    }

    global class ResponseDTO {
        public Boolean success;
        public String  message;
        public List<ProjectDTO> projects;
    }

    @HttpPost
    global static ResponseDTO getProjects() {

        ResponseDTO resp = new ResponseDTO();
        resp.success = false;
        resp.projects = new List<ProjectDTO>();

        try {
            String raw = RestContext.request.requestBody == null ? null
                         : RestContext.request.requestBody.toString();

            Map<String, Object> input = (raw == null || raw.trim() == '')
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(raw);

            String contactId = (String) input.get('contactId');
            if (String.isBlank(contactId)) {
                resp.message = 'Missing Contact Id';
                return resp;
            }

            // ✅ Correct: Project__c has Client__c lookup(Contact)
            List<Project__c> projects = [
                SELECT Id,
                    Name,
                    Status__c,
                    Supervisor_Estimated_Budget__c,
                    Start_Date__c,
                    End_Date__c,
                    Project_Completion_Status__c,
                    Client__c
                FROM Project__c
                WHERE Client__c = :contactId
                ORDER BY CreatedDate DESC
            ];

            for (Project__c p : projects) {
                ProjectDTO dto = new ProjectDTO();
                dto.projectId = p.Id;
                dto.projectName = p.Name;
                dto.projectStatus = p.Status__c;
                dto.budget = p.Supervisor_Estimated_Budget__c;
                dto.startDate = p.Start_Date__c;
                dto.endDate = p.End_Date__c;
                dto.completionPercentage = p.Project_Completion_Status__c;
                dto.vendors = new List<VendorDTO>();

                List<Vendor_Assignment__c> vas = [
                    SELECT Vendor__r.Name,
                           Vendor_Category__c,
                           Completion__c,
                           Vendor_Work_Start_Date__c,
                           Vendor_Work_End_Date__c,
                           Vendor_Tasks_Remaining_Percentage__c,
                           Project__c
                    FROM Vendor_Assignment__c
                    WHERE Project__c = :p.Id
                ];

                for (Vendor_Assignment__c va : vas) {
                    VendorDTO v = new VendorDTO();
                    v.vendorName = (va.Vendor__r == null) ? null : va.Vendor__r.Name;
                    v.vendorCategory = String.valueOf(va.Vendor_Category__c);
                    v.completionPercentage = va.Completion__c;
                    v.startDate = va.Vendor_Work_Start_Date__c;
                    v.endDate = va.Vendor_Work_End_Date__c;
                    v.remainingTasks = va.Vendor_Tasks_Remaining_Percentage__c;
                    dto.vendors.add(v);
                }

                resp.projects.add(dto);
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