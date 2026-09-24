public with sharing class DisputeEscalationService {

    //for Part1(i)
    public static void stampDisputeOpenedOn(List<Booking__c> newBookings, Map<Id, Booking__c> oldMap) {
        for (Booking__c b : newBookings) {
            Boolean isDisputed = (b.Status__c == 'Disputed');
            Boolean wasDisputed = (oldMap != null && oldMap.containsKey(b.Id) && oldMap.get(b.Id).Status__c == 'Disputed');

            if (isDisputed && !wasDisputed) {  b.Dispute_Opened_On__c = System.now();}
        }
    }

    // this checks the triggered booking are newly disputed or not, collect their ownerIds in a set for further processing
    public static void processDisputedBookings(List<Booking__c> newBookings, Map<Id, Booking__c> oldMap) {
        Set<Id> ownerIdsToProcess = new Set<Id>();

        for (Booking__c b : newBookings) {
            Boolean isDisputed = (b.Status__c == 'Disputed');
            Boolean wasDisputed = (oldMap != null && oldMap.containsKey(b.Id) && oldMap.get(b.Id).Status__c == 'Disputed');
            if (isDisputed && !wasDisputed && b.OwnerId != null) { ownerIdsToProcess.add(b.OwnerId);}
        }
        if (!ownerIdsToProcess.isEmpty()) { addOwnersToDisputeGroupAsync(ownerIdsToProcess);}
    }

    @future
    public static void addOwnersToDisputeGroupAsync(Set<Id> ownerIds) {
        try {
            List<Group> groups = [ SELECT Id  FROM Group  WHERE DeveloperName = 'Open_Dispute_Owners' OR Name = 'Open Dispute Owners'  LIMIT 1];
            if (groups.isEmpty()) { logError('Public Group "Open Dispute Owners" not found.'); return;}
            Id groupId = groups[0].Id;

            Set<Id> existingMemberIds = new Set<Id>();
            for (GroupMember gm : [ SELECT UserOrGroupId  FROM GroupMember  WHERE GroupId = :groupId AND UserOrGroupId IN :ownerIds ]) {
                existingMemberIds.add(gm.UserOrGroupId);
            }

            List<GroupMember> newMembers = new List<GroupMember>();
            for (Id ownerId : ownerIds) {
                if (!existingMemberIds.contains(ownerId) && String.valueOf(ownerId).startsWith('005')) {
                    newMembers.add(new GroupMember(GroupId = groupId,UserOrGroupId = ownerId));
                }
            }

            if (!newMembers.isEmpty()) {
                List<Database.SaveResult> results = Database.insert(newMembers, false);
                for (Database.SaveResult sr : results) {
                    if (!sr.isSuccess()) {
                        String errMsg = '';
                        for (Database.Error err : sr.getErrors()) {errMsg += err.getMessage() + ' ';}
                        logError('Failed to insert GroupMember: ' + errMsg);
                    }
                }
            }
        } catch (Exception e) {
            logError('Error in addOwnersToDisputeGroupAsync: ' + e.getMessage() + ' | ' + e.getStackTraceString());
        }
    }

    private static void logError(String message) {
        try {
            Schema.SObjectType logType = Schema.getGlobalDescribe().get('Error_Log__c');
            if (logType != null) {
                sObject log = logType.newSObject();
                Map<String, Schema.SObjectField> fields = logType.getDescribe().fields.getMap();

                if (fields.containsKey('error_message__c')) log.put('error_message__c', message);
                else if (fields.containsKey('message__c')) log.put('message__c', message);
                else if (fields.containsKey('details__c')) log.put('details__c', message);

                if (fields.containsKey('source__c')) log.put('source__c', 'DisputeEscalationService');
                else if (fields.containsKey('class_name__c')) log.put('class_name__c', 'DisputeEscalationService');

                insert log;
            }
        } catch (Exception ex) {
           
        }
    }
}