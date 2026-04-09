trigger CaseTrigger on Case (before insert, before update) {

    if (Trigger.isBefore) {
        if (Trigger.isInsert || Trigger.isUpdate) {
            CaseTriggerHandler.assignCases(Trigger.new);
        }
    }
}