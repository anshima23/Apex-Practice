trigger RoomTrigger on Room__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        RoomTriggerHandler.handleBefore(Trigger.new);
    } else if (Trigger.isAfter) {
        RoomTriggerHandler.handleAfter(Trigger.new);
    }
}