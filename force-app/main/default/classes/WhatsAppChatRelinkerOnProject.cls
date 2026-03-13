public without sharing class WhatsAppChatRelinkerOnProject {

    /**
     * After INSERT: for each new Project that has Opportunity__c,
     * set Project__c on WhatsApp_Chat__c records for that Opportunity
     * (without overwriting if Project__c is already set).
     */
    public static void onAfterInsert(List<Project__c> newList) {
        if (newList == null || newList.isEmpty()) return;

        // choose one project per Opportunity from this batch (newest in the batch)
        Map<Id, Id> oppToProject = pickProjectPerOpp(newList);

        linkChatsToProjects(oppToProject);
    }

    /**
     * After UPDATE: if a Project’s Opportunity__c was populated/changed,
     * relink chats for the new Opportunity (no overwrite).
     */
    public static void onAfterUpdate(List<Project__c> newList, Map<Id, Project__c> oldMap) {
        if (newList == null || newList.isEmpty()) return;

        List<Project__c> affected = new List<Project__c>();
        for (Project__c p : newList) {
            Project__c oldP = oldMap.get(p.Id);
            // Run when Opp was set for the first time OR changed to another Opp
            Boolean becameSet = (p.Project_Name__c != null) &&
                                (oldP == null || oldP.Project_Name__c != p.Project_Name__c);
            if (becameSet) affected.add(p);
        }
        if (affected.isEmpty()) return;

        Map<Id, Id> oppToProject = pickProjectPerOpp(affected);
        linkChatsToProjects(oppToProject);
    }

    /**
     * Pick one Project per Opportunity from the provided list.
     * Default: newest by CreatedDate among those rows.
     * If you have a flag like Is_Primary__c, prefer that (see comment).
     */
    private static Map<Id, Id> pickProjectPerOpp(List<Project__c> projects) {
        Map<Id, Id> oppToProject = new Map<Id, Id>();
        Map<Id, Datetime> oppToTs = new Map<Id, Datetime>();

        for (Project__c p : projects) {
            if (p.Project_Name__c == null) continue;

            // If you have Is_Primary__c, you can short-circuit preference here, e.g.:
            // if (p.Is_Primary__c == true) { oppToProject.put(p.Opportunity__c, p.Id); continue; }

            Datetime ts = (Datetime)p.get('CreatedDate');
            Datetime haveTs = oppToTs.get(p.Project_Name__c);
            if (haveTs == null || (ts != null && ts.getTime() > haveTs.getTime())) {
                oppToTs.put(p.Project_Name__c, ts);
                oppToProject.put(p.Project_Name__c, p.Id);
            }
        }
        return oppToProject;
    }

    /**
     * Core relink: for each Opportunity → Project chosen,
     * set WhatsApp_Chat__c.Project__c where it’s currently null.
     */
    private static void linkChatsToProjects(Map<Id, Id> oppToProject) {
        if (oppToProject.isEmpty()) return;

        // Fetch chats on those Opportunities that don't yet have a Project
        List<WhatsApp_Chat__c> chats = [
            SELECT Id, Opportunity__c, Project__c
            FROM WhatsApp_Chat__c
            WHERE Opportunity__c IN :oppToProject.keySet()
              AND Project__c = NULL
        ];
        if (chats.isEmpty()) return;

        List<WhatsApp_Chat__c> updates = new List<WhatsApp_Chat__c>();
        for (WhatsApp_Chat__c c : chats) {
            Id projId = oppToProject.get(c.Opportunity__c);
            if (projId != null) {
                c.Project__c = projId; // do not overwrite if already set (query ensures null)
                updates.add(c);
            }
        }
        if (!updates.isEmpty()) update updates;
    }
}