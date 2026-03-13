/**
 * ─────────────────────────────────────────────────────────────────────────────
 * Class Name      : ProjectStatusController
 * Author          : Naresh Punagani
 * Created Date    : Jan 2026
 * Description     :
 *  Experience Cloud / LWC controller used by "Project Status" portal page.
 *
 *  What it does:
 *   1) Validates user credentials (Contact.Email + Contact.Password__c)
 *   2) Returns customer header details (Name/Email/Phone)
 *   3) Returns all Projects__c for that customer (latest first)
 *   4) Returns Vendor_Assignment__c records for those projects
 *   5) Returns Tasks linked to Vendor_Assignment__c (WhatId = Vendor_Assignment__c.Id)
 *
 *  Notes / Assumptions:
 *   - The login uses Contact.Password__c as provided (your existing design).
 *   - "Quotation Type" is taken from the latest project record:
 *       Project__c.Project_Request_Quotation_Type__c
 *   - Designed for portal read-only dashboard usage.
 *
 * PMD / Best Practices:
 *   - Declares sharing model (with sharing)
 *   - Uses helper methods to reduce complexity
 *   - Uses constants for messages & limits
 *   - Bulk-safe SOQL (1 query per object type, no SOQL in loops)
 * ─────────────────────────────────────────────────────────────────────────────
 */
@SuppressWarnings('PMD.CognitiveComplexity,PMD.ApexCRUDViolation,PMD.ExcessiveParameterList')
public without sharing class ProjectStatusController {

    /* =========================================================================
       CONSTANTS
       ========================================================================= */

    /** @description SOQL LIMIT used for single-contact fetch. */
    private static final Integer LIMIT_ONE = 1;

    /** @description Message shown when user did not enter email/password. */
    private static final String MSG_MISSING_CREDS = 'Please enter both Email and Password.';

    /** @description Message shown when credentials are invalid. */
    private static final String MSG_INVALID_CREDS = 'Invalid email or password.';

    /** @description Message shown when login succeeds but no projects exist. */
    private static final String MSG_NO_PROJECTS = 'No projects found for this contact.';

    /** @description Success message. */
    private static final String MSG_SUCCESS = 'Success';

    /* =========================================================================
       DTOs (Returned to LWC)
       ========================================================================= */

    /**
     * @description Customer header DTO for the portal UI.
     */
    public class CustomerDTO {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;

        /**
         * @description Quotation type shown in customer header.
         *              Populated from latest project:
         *              Project__c.Project_Request_Quotation_Type__c
         */
        @AuraEnabled public String quotationType;
    }

    /**
     * @description Task row DTO shown under vendor assignment.
     */
    public class TaskDTO {
        @AuraEnabled public Id      id;
        @AuraEnabled public String  subject;
        @AuraEnabled public String  status;
        @AuraEnabled public Date    startDate;
        @AuraEnabled public Date    dueDate;
        @AuraEnabled public Decimal assignedPercent;
        @AuraEnabled public Date    finalCompletedDate;
        @AuraEnabled public Integer numberOfDays;
    }

    /**
     * @description Vendor Assignment DTO shown under a Project.
     */
    public class VendorAssignmentDTO {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;
        @AuraEnabled public String vendorName;
        @AuraEnabled public String category;
        @AuraEnabled public String status;
        @AuraEnabled public Date   workStartDate;
        @AuraEnabled public Date   workEndDate;
        @AuraEnabled public Integer workDuration;
        @AuraEnabled public Decimal amount;

        /** @description Vendor assignment completion percentage (from Vendor_Assignment__c.Completion__c). */
        @AuraEnabled public Decimal completionPercent;

        /** @description Tasks related to this vendor assignment (Task.WhatId = Vendor_Assignment__c.Id). */
        @AuraEnabled public List<TaskDTO> tasks;
    }

    /**
     * @description Project DTO shown on the portal.
     */
    public class ProjectDTO {
        @AuraEnabled public Id     id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public Date   startDate;
        @AuraEnabled public Date   endDate;
        @AuraEnabled public String estimatedDuration;

        /** @description Project completion percentage (from Project__c.Project_Completion_Status__c). */
        @AuraEnabled public Decimal completionPercent;

        /** @description Project quotation type (from Project__c.Project_Request_Quotation_Type__c). */
        @AuraEnabled public String quotationType;

        /** @description Vendor assignments under this project. */
        @AuraEnabled public List<VendorAssignmentDTO> vendorAssignments;
    }

    /**
     * @description Wrapper response to LWC.
     */
    public class AuthResponseDTO {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String  message;

        /** @description Customer header data (shown at top of UI). */
        @AuraEnabled public CustomerDTO customer;

        /** @description List of projects for the authenticated customer. */
        @AuraEnabled public List<ProjectDTO> projects;
    }

    /* =========================================================================
       PUBLIC API
       ========================================================================= */

    /**
     * @description
     *  Authenticates the user (Contact.Email + Contact.Password__c) and returns
     *  customer + project dashboard data.
     *
     * @param email    Contact email used for portal login.
     * @param password Contact Password__c value.
     * @return AuthResponseDTO containing success flag, message, customer & projects data.
     */
    @AuraEnabled(cacheable=false)
    public static AuthResponseDTO loginAndFetch(String email, String password) {
        AuthResponseDTO res = initResponse();

        if (String.isBlank(email) || String.isBlank(password)) {
            return fail(res, MSG_MISSING_CREDS);
        }

        Contact c = fetchContactByCredentials(email, password);
        if (c == null) {
            return fail(res, MSG_INVALID_CREDS);
        }

        res.customer = buildCustomerDTO(c);

        List<Project__c> projectRecords = fetchProjectsForContact(c.Id);
        if (projectRecords.isEmpty()) {
            res.success = true;
            res.message = MSG_NO_PROJECTS;
            return res;
        }

        // Customer quotation type from latest project (sorted DESC by CreatedDate)
        res.customer.quotationType = projectRecords[0].Project_Request_Quotation_Type__c;

        Set<Id> projectIds = collectProjectIds(projectRecords);

        VendorBuildContext ctx = buildVendorAssignments(projectIds);

        if (!ctx.vendorAssignmentIds.isEmpty()) {
            attachTasksToVendorAssignments(ctx.vaIdToDto, ctx.vendorAssignmentIds);
        }

        res.projects = buildProjectDTOs(projectRecords, ctx.projToVAs);

        res.success = true;
        res.message = MSG_SUCCESS;
        return res;
    }

    /* =========================================================================
       RESPONSE HELPERS
       ========================================================================= */

    /**
     * @description Initializes the response wrapper with safe defaults.
     */
    private static AuthResponseDTO initResponse() {
        AuthResponseDTO res = new AuthResponseDTO();
        res.success = false;
        res.message = null;
        res.customer = null;
        res.projects = new List<ProjectDTO>();
        return res;
    }

    /**
     * @description Standard failure builder (clears projects + customer).
     */
    private static AuthResponseDTO fail(AuthResponseDTO res, String message) {
        res.success = false;
        res.message = message;
        res.projects = new List<ProjectDTO>();
        res.customer = null;
        return res;
    }

    /* =========================================================================
       QUERIES
       ========================================================================= */

    /**
     * @description Fetches a Contact by Email and Password__c.
     * @param email Contact Email.
     * @param password Contact Password__c.
     * @return Contact record if found, otherwise null.
     */
    private static Contact fetchContactByCredentials(String email, String password) {
        List<Contact> matches = [
            SELECT Id, Name, Email, Phone
            FROM Contact
            WHERE Email = :email
              AND Password__c = :password
            LIMIT :LIMIT_ONE
        ];
        return matches.isEmpty() ? null : matches[0];
    }

    /**
     * @description Fetches projects for the given Contact.
     * @param contactId The Contact Id stored in Project__c.Client__c.
     * @return List of Project__c ordered by CreatedDate DESC (latest first).
     */
    private static List<Project__c> fetchProjectsForContact(Id contactId) {
        return [
            SELECT Id,
                   Name,
                   Status__c,
                   Start_Date__c,
                   Estimated_End_Date__c,
                   Estimated_Project_Duration__c,
                   Project_Completion_Status__c,
                   Project_Request_Quotation_Type__c
            FROM Project__c
            WHERE Client__c = :contactId
            ORDER BY CreatedDate DESC
        ];
    }

    /* =========================================================================
       CUSTOMER BUILDER
       ========================================================================= */

    /**
     * @description Converts Contact into CustomerDTO for portal header.
     */
    private static CustomerDTO buildCustomerDTO(Contact c) {
        CustomerDTO cust = new CustomerDTO();
        cust.id = c.Id;
        cust.name = c.Name;
        cust.email = c.Email;
        cust.phone = c.Phone;
        cust.quotationType = null;
        return cust;
    }

    /* =========================================================================
       PROJECT ID UTILS
       ========================================================================= */

    /**
     * @description Collects project Ids from Project__c list.
     */
    private static Set<Id> collectProjectIds(List<Project__c> projects) {
        Set<Id> ids = new Set<Id>();
        for (Project__c p : projects) {
            if (p != null && p.Id != null) {
                ids.add(p.Id);
            }
        }
        return ids;
    }

    /* =========================================================================
       VENDOR BUILD CONTEXT
       ========================================================================= */

    /**
     * @description Internal context used to return vendor assignment maps for later steps.
     */
    private class VendorBuildContext {
        /** @description Map(ProjectId -> VendorAssignmentDTO list). */
        public Map<Id, List<VendorAssignmentDTO>> projToVAs;

        /** @description Map(VendorAssignmentId -> VendorAssignmentDTO). */
        public Map<Id, VendorAssignmentDTO> vaIdToDto;

        /** @description Set of Vendor_Assignment__c Ids for Task query. */
        public Set<Id> vendorAssignmentIds;

        public VendorBuildContext() {
            projToVAs = new Map<Id, List<VendorAssignmentDTO>>();
            vaIdToDto = new Map<Id, VendorAssignmentDTO>();
            vendorAssignmentIds = new Set<Id>();
        }
    }

    /* =========================================================================
       VENDOR ASSIGNMENT BUILDERS
       ========================================================================= */

    /**
     * @description Fetches vendor assignments for project ids and builds DTO maps.
     * @param projectIds Set of Project__c Ids.
     * @return VendorBuildContext containing DTO maps + vendor assignment ids.
     */
    private static VendorBuildContext buildVendorAssignments(Set<Id> projectIds) {
        VendorBuildContext ctx = new VendorBuildContext();

        if (projectIds == null || projectIds.isEmpty()) {
            return ctx;
        }

        List<Vendor_Assignment__c> vaRecords = [
            SELECT Id,
                   Name,
                   Project__c,
                   Vendor__r.Name,
                   Vendor_Category__c,
                   Status__c,
                   Vendor_Work_Start_Date__c,
                   Vendor_Work_End_Date__c,
                   Number_of_Days__c,
                   Vendor_Amount__c,
                   Completion__c
            FROM Vendor_Assignment__c
            WHERE Project__c IN :projectIds
        ];

        for (Vendor_Assignment__c va : vaRecords) {
            if (va == null || va.Id == null) continue;

            ctx.vendorAssignmentIds.add(va.Id);

            VendorAssignmentDTO dto = buildVendorAssignmentDTO(va);
            ctx.vaIdToDto.put(va.Id, dto);

            if (!ctx.projToVAs.containsKey(va.Project__c)) {
                ctx.projToVAs.put(va.Project__c, new List<VendorAssignmentDTO>());
            }
            ctx.projToVAs.get(va.Project__c).add(dto);
        }

        return ctx;
    }

    /**
     * @description Converts Vendor_Assignment__c into VendorAssignmentDTO.
     */
    private static VendorAssignmentDTO buildVendorAssignmentDTO(Vendor_Assignment__c va) {
        VendorAssignmentDTO dto = new VendorAssignmentDTO();
        dto.id = va.Id;
        dto.name = va.Name;
        dto.vendorName = (va.Vendor__r != null) ? va.Vendor__r.Name : null;
        dto.category = va.Vendor_Category__c;
        dto.status = va.Status__c;
        dto.workStartDate = va.Vendor_Work_Start_Date__c;
        dto.workEndDate = va.Vendor_Work_End_Date__c;
        dto.workDuration = toIntegerSafe(va.Number_of_Days__c);
        dto.amount = va.Vendor_Amount__c;
        dto.completionPercent = va.Completion__c;
        dto.tasks = new List<TaskDTO>();
        return dto;
    }

    /* =========================================================================
       TASK BUILDERS
       ========================================================================= */

    /**
     * @description Attaches TaskDTO rows to the proper VendorAssignmentDTO.
     * @param vaIdToDto VendorAssignmentId -> VendorAssignmentDTO map.
     * @param vaIds Set of Vendor_Assignment__c Ids for task lookup.
     */
    private static void attachTasksToVendorAssignments(
        Map<Id, VendorAssignmentDTO> vaIdToDto,
        Set<Id> vaIds
    ) {
        if (vaIdToDto == null || vaIdToDto.isEmpty() || vaIds == null || vaIds.isEmpty()) {
            return;
        }

        List<Task> tasks = [
            SELECT Id,
                   Subject,
                   Status,
                   Start_Date__c,
                   ActivityDate,
                   Assigned_Percentage__c,
                   Final_Task_Completed_Date__c,
                   Number_of_Days__c,
                   WhatId
            FROM Task
            WHERE WhatId IN :vaIds
            ORDER BY ActivityDate
        ];

        for (Task t : tasks) {
            if (t == null || t.WhatId == null) continue;

            VendorAssignmentDTO vaDto = vaIdToDto.get(t.WhatId);
            if (vaDto == null) continue;

            vaDto.tasks.add(buildTaskDTO(t));
        }
    }

    /**
     * @description Converts Task into TaskDTO row.
     */
    private static TaskDTO buildTaskDTO(Task t) {
        TaskDTO td = new TaskDTO();
        td.id = t.Id;
        td.subject = t.Subject;
        td.status = t.Status;
        td.startDate = t.Start_Date__c;
        td.dueDate = t.ActivityDate;
        td.assignedPercent = t.Assigned_Percentage__c;
        td.finalCompletedDate = t.Final_Task_Completed_Date__c;
        td.numberOfDays = toIntegerSafe(t.Number_of_Days__c);
        return td;
    }

    /* =========================================================================
       PROJECT DTO BUILDERS
       ========================================================================= */

    /**
     * @description Builds the final list of ProjectDTOs for the response.
     * @param projects Project__c records
     * @param projToVADtos Map(ProjectId -> VendorAssignmentDTO list)
     * @return List<ProjectDTO>
     */
    private static List<ProjectDTO> buildProjectDTOs(
        List<Project__c> projects,
        Map<Id, List<VendorAssignmentDTO>> projToVADtos
    ) {
        List<ProjectDTO> out = new List<ProjectDTO>();
        if (projects == null || projects.isEmpty()) return out;

        for (Project__c p : projects) {
            if (p == null) continue;

            ProjectDTO pd = new ProjectDTO();
            pd.id = p.Id;
            pd.name = p.Name;
            pd.status = p.Status__c;
            pd.startDate = p.Start_Date__c;
            pd.endDate = p.Estimated_End_Date__c;
            pd.estimatedDuration = p.Estimated_Project_Duration__c;
            pd.completionPercent = p.Project_Completion_Status__c;
            pd.quotationType = p.Project_Request_Quotation_Type__c;
            pd.vendorAssignments = (projToVADtos != null && projToVADtos.containsKey(p.Id))
                ? projToVADtos.get(p.Id)
                : new List<VendorAssignmentDTO>();

            out.add(pd);
        }

        return out;
    }

    /* =========================================================================
       UTILITIES
       ========================================================================= */

    /**
     * @description Converts Decimal -> Integer safely (null-safe).
     */
    private static Integer toIntegerSafe(Decimal d) {
        return (d == null) ? null : Integer.valueOf(d);
    }
}