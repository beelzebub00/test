/**
 * @author Noeli
 * @date Creation 21/07/2020
 * @description: class to create new WorkOrder record of type C in staging table for later dispatcher notification.
 * @testedIn Plc_InsertWorkOrderStagingCTest
 */
public with sharing class Plc_WorkOrderInsertStagingC {

    static final String WORKORDER_CANCELLED_STATE = 'Annullo definitivo';
    static final String WORKORDER_CANCELLED_REASIGNMENT = 'Annullo per riassegnazione';
    static final String WORKORDER_CANCELLED_PARTIAL = 'Annullo parziale';
    static final String WORKORDER_URGENCY_STATE = 'Urgenza';
    static final String WORKORDER_REMINDER_STATE = 'Sollecito';
    static final String WORKORDER_SUSPENSION_EFFECTIVE_STATE = 'Sospensione effettiva';
    static final String WORKORDER_SUSPENSION_REFUSED_STATE = 'Sospensione rifiutata';
    static final String WORKORDER_REFUSAL_ADDITIONALCOST_STATE = 'Rifiuto costi aggiuntivi';
    // static final String WORKORDER_REFUSAL_EMPTY_EXIT_STATE = 'Uscita a vuoto';
    static final String WORKORDER_REFUSAL_EMPTY_EXIT_STATE = 'Uscita a vuoto rifiutata';
    static final String WORKORDER_REACTIVATION_STATE = 'Riattivazione';
    static final String DISPATCHER_USER_PROFILE = 'Dispatcher';
    static final String OPERATION_USER_PROFILE = 'Operation';
    static final String MAGAZZINIERE_USER_PROFILE='Magazziniere';

    static String notifyWoState;
    
    static Map<Id,List<WorkOrderLineItem>> allWolisMap;
    static Map<Id,List<Expense>> allWoExpsMap;
    static Map<Id,List<Plc_UnsuccessfulExit__c>> allUnsfExitRsMap;

    static public String queryString =
    'SELECT Id, Plc_SystemVersion__c, WorkOrderNumber, WorkType.Name, Account.Name,' +
    'Plc_Signboard__c, Plc_OperationLocality__c,Plc_Dealer__c,Status,Plc_Urgency__c,Plc_Reminder__c,' +
    'Plc_LockStatus__c,IsStopped,Plc_LockReason__c,Plc_Alias__c,Plc_SDMAssignmentDate__c,Plc_UrgencyDate__c,'+
    'Plc_Note__c,Plc_TroubleTicket__c,Plc_OperationPostalCode__c,Plc_OperationProvince__c,Plc_BankNote__c,'+
    'Plc_Prefix__c,Plc_Phone__c,Plc_AlternativePhone__c,Plc_Contact__c,wo.RecordType.Name,Plc_SiaCode__c,'+
    'Plc_Vat__c,Plc_OperationAddress__c,Plc_ServicePoint__c,Plc_BankDescription__c,'+
    'State,Plc_SourceLegacySystem__c,Plc_WorkReportNote__c, WorkTypeId,'+
    'Plc_ClientType__c, Plc_ClientTypeName__c,  Plc_OpeningTime__c, Plc_BreakStartTime__c, Plc_BreakEndTime__c,'+
    'Plc_EndingTime__c,Plc_OpeningMondayMorning__c, Plc_OpeningMondayAfternoon__c, Plc_OpeningTuesdayMorning__c, Plc_OpeningTuesdayAfternoon__c, '+
    'Plc_OpeningWednesdayMorning__c, Plc_OpeningWednesdayAfternoon__c, Plc_OpeningThursdayMorning__c, Plc_OpeningThursdayAfternoon__c, '+
    'Plc_OpeningFridayMorning__c, Plc_OpeningFridayAfternoon__c, Plc_OpeningSaturdayMorning__c, Plc_OpeningSaturdayAfternoon__c, '+
    'Plc_OpeningSundayMorning__c, Plc_OpeningSundayAfternoon__c, Plc_WeeklyClosing__c,'+
    'Plc_ServiceType__c, Plc_Abi__c,Plc_ExpirationSlaDate__c,LastModifiedById FROM WorkOrder wo ' +
    'Where Id IN ';


    public static void insertWOStagingCForNotification(List<SObject> newItems, List<SObject> oldItems,
                                                       Boolean isWoli, Boolean isUnsfExit, Boolean isExpense){

        allWolisMap = getWorkOrderLineItems(newItems);
        allWoExpsMap = getWoExpenses(newItems);
        allUnsfExitRsMap = getWoUnsuccessfulExitReasons(newItems);

        System.debug('allWolisMap size: '+allWolisMap.size());

        for (WorkOrder wo : (List<WorkOrder>) newItems) {
            System.debug('isWoli: '+isWoli);
            System.debug('isUnsfExit: '+isUnsfExit);
            System.debug('isExpense: '+isExpense);
            System.debug('wo.Plc_SystemVersion__c: '+wo.Plc_SystemVersion__c);
            if((isWoli == false && isUnsfExit == false && isExpense == false)
               &&
               (getDispatcherUsers().containsKey(wo.LastModifiedById) ||
                getMagazziniereUsers().containsKey(wo.LastModifiedById) ||
                wo.Plc_SystemVersion__c == 'LOG' || 
                wo.Plc_SystemVersion__c == null)) {

                    System.debug('skipping email');
                    continue;
            }

            notifyWoState = verifyWONotifyState(wo,oldItems,isWoli,isUnsfExit,isExpense);
            System.debug('Wo notify state: '+notifyWoState);
            if(String.isEmpty(notifyWoState)) { continue; }

            insertWOStagingC(wo,notifyWoState);
        }
    }

    public static void WORelatedStagingCForNotification(Id woId, Boolean isWoli,Boolean isUnsfExit, Boolean isExpense){
        Set<Id> woIds= new Set<Id>{woId};
        String query = queryString+':woIds';
        List<WorkOrder> wo = Database.query(query);
        insertWOStagingCForNotification(wo,wo,isWoli,isUnsfExit,isExpense);
    }

    public static String verifyWONotifyState(WorkOrder wo, List<WorkOrder> oldItems, Boolean isWoli,Boolean isUnsfExit, Boolean isExpense){

        Map<Id,WorkOrder> MapOldWos =  new Map<Id,WorkOrder>(oldItems);

        if(MapOldWos.get(wo.Id).Status=='Assigned' && wo.Status=='Canceled') {
            return WORKORDER_CANCELLED_STATE;
        }
        else if(isWoli && isWOWOLINotExecuted(wo)) {
            return WORKORDER_CANCELLED_PARTIAL;
        }
        else if(!MapOldWos.get(wo.Id).Plc_Urgency__c && wo.Plc_Urgency__c &&
                wo.Status=='Assigned') {
            return WORKORDER_URGENCY_STATE;
        }
        else if(!MapOldWos.get(wo.Id).Plc_Reminder__c && wo.Plc_Reminder__c &&
                wo.Status=='Assigned') {
            return WORKORDER_REMINDER_STATE;
        }
        else if(MapOldWos.get(wo.Id).Plc_LockStatus__c != 'Locked' &&
                wo.Plc_LockStatus__c=='Locked' &&
                wo.Status=='Assigned') {
            return WORKORDER_SUSPENSION_EFFECTIVE_STATE;
        }
        else if(MapOldWos.get(wo.Id).Plc_LockStatus__c == 'In approval' &&
                String.IsEmpty(wo.Plc_LockStatus__c) &&
                wo.Status=='Assigned') {
            return WORKORDER_SUSPENSION_REFUSED_STATE;
        }
        else if(isExpense && isWOExpenseRejected(wo) &&
                wo.Status=='Assigned') {
            return WORKORDER_REFUSAL_ADDITIONALCOST_STATE;
        }
        else if(isUnsfExit && isUnsuccessfulExitReason(wo) &&
                wo.Status=='Assigned') {
            return WORKORDER_REFUSAL_EMPTY_EXIT_STATE;
        }
        else if((String.isNotEmpty(MapOldWos.get(wo.Id).Plc_LockStatus__c) && String.isEmpty(wo.Plc_LockStatus__c)) &&
                (String.isNotEmpty(MapOldWos.get(wo.Id).Plc_LockReason__c) && String.isEmpty(wo.Plc_LockReason__c)) &&
                (MapOldWos.get(wo.Id).Plc_LockStatus__c=='Locked' && String.isEmpty(wo.Plc_LockStatus__c)) &&
                wo.Status=='Assigned') {
            return WORKORDER_REACTIVATION_STATE;
        }
        else {
            return null;
        }
    }

    public static void insertWOStagingC(WorkOrder wo, String NfyWoState){

        Plc_StandingWO__c[] existwosc = [SELECT Id,Name,Plc_Status__c FROM Plc_StandingWO__c 
                                         WHERE Plc_WorkOrder__c= :wo.Id 
                                           AND Plc_Type__c = 'standingC' 
                                           AND Name = :NfyWoState 
                                           AND (Plc_Status__c = 'Waiting' OR Plc_Status__c = 'Running')];

        if(existwosc.size()==0){
            Plc_StandingWO__c  wosc = new Plc_StandingWO__c (
                Name=NfyWoState,
                Plc_Type__c='standingC',
                Plc_WorkOrder__c=wo.Id
            );
            insert wosc;
        }
    }


    public static Boolean isWOWOLINotExecuted(WorkOrder wo){
        if(!allWolisMap.isEmpty() && allWolisMap.get(wo.Id)!=null){
            for(WorkOrderLineItem woLi : allWolisMap.get(wo.Id)){
                if(woLi.Status  =='NotExecuted')return true;
            }
        }
        return false;
    }

   public static Boolean isWOExpenseRejected(WorkOrder wo){
       if(!allWoExpsMap.isEmpty() && allWoExpsMap.get(wo.Id)!=null){
            for(Expense woExp : allWoExpsMap.get(wo.Id)){
                if(woExp.Plc_Status__c=='Rejected')return true;
            }
        }
        return false;
    }

    public static Boolean isUnsuccessfulExitReason(WorkOrder wo){
        if(!allUnsfExitRsMap.isEmpty() && allUnsfExitRsMap.get(wo.id)!=null){
            for(Plc_UnsuccessfulExit__c UnsfExitR : allUnsfExitRsMap.get(wo.id)){
                if(UnsfExitR.Plc_Status__c=='Rejected') return true;
            }
        }
        return false;
    }
    public static Map<id,User> getDispatcherUsers(){

        return getUsers().get(DISPATCHER_USER_PROFILE);
    }

    public static Map<id,User> getOperationUsers(){

        return getUsers().get(OPERATION_USER_PROFILE);
    }

    public static Map<id,User> getMagazziniereUsers(){

        return getUsers().get(MAGAZZINIERE_USER_PROFILE);
    }

    static User[] users;
    static Map<Id,User> allOperators;
    static Map<Id,User> allDispatchers;
    static Map<Id,User> allMagazzinieres;
    public static Map<String,Map<Id,User>> getUsers(){

        if(users==null){
            users = [SELECT Id,Name,Email,ProfileId,Profile.Name FROM User
                         WHERE Profile.Name in (:MAGAZZINIERE_USER_PROFILE,:DISPATCHER_USER_PROFILE,:OPERATION_USER_PROFILE)
                    ];

        }
        if(allMagazzinieres==null){
            allOperators= new Map<Id,User>();
            allDispatchers=new Map<Id,User>();
            allMagazzinieres=new Map<Id,User>();

            for(User u :users){
                if(u.Profile.Name==MAGAZZINIERE_USER_PROFILE){
                    allMagazzinieres.put(u.Id, u);
                }
                if(u.Profile.Name==DISPATCHER_USER_PROFILE){
                    allDispatchers.put(u.Id, u);
                }
                if(u.Profile.Name==OPERATION_USER_PROFILE){
                    allOperators.put(u.Id, u);
                }
            }
        }

        //return null;
       return new Map<String,Map<Id,User>>{
            MAGAZZINIERE_USER_PROFILE=>allMagazzinieres,
            DISPATCHER_USER_PROFILE=>allDispatchers,
            OPERATION_USER_PROFILE=>allOperators
       };
    }

    public static Map<Id,List<WorkOrderLineItem>> getWorkOrderLineItems(List<WorkOrder> newItems){
        Map<Id,WorkOrder> NewWosMap =  new Map<Id,WorkOrder>(newItems);
        Map<Id,List<WorkOrderLineItem>> woLisMap = new Map<Id,List<WorkOrderLineItem>>();
        WorkOrderLineItem[] allWoLis = [SELECT Id, WorkOrderId,Status FROM WorkOrderLineItem WHERE WorkOrderId IN :NewWosMap.keyset()];
        for(WorkOrder wo : NewWosMap.values()){
            List<WorkOrderLineItem> woLis = new List<WorkOrderLineItem>();
            for(WorkOrderLineItem woLi :allWoLis){
                if(woLi.WorkOrderId==wo.Id)woLis.add(woLi);
            }
            if(!woLis.isEmpty())woLisMap.put(wo.id,woLis);
        }

        return woLisMap;
    }

    public static Map<Id,List<Expense>> getWoExpenses(List<WorkOrder> newItems){
        Map<Id,WorkOrder> NewWosMap =  new Map<Id,WorkOrder>(newItems);
        Map<Id,List<Expense>>  woExpsMap = new Map<Id,List<Expense>>();
        Expense[] allWoExpsList = [SELECT Id, WorkOrderId,Plc_Status__c  FROM Expense WHERE WorkOrderId IN :NewWosMap.keyset()];
         for(WorkOrder wo : NewWosMap.values()){
            List<Expense> woExps = new List<Expense>();
            for(Expense woExp : allWoExpsList){
                if(woExp.WorkOrderId==wo.Id)woExps.add(woExp);
            }
            if(!woExps.isEmpty())woExpsMap.put(wo.id,woExps);
        }
        return woExpsMap;
    }

    public static Map<Id,List<Plc_UnsuccessfulExit__c>> getWoUnsuccessfulExitReasons(List<WorkOrder> newItems){
        Map<Id,WorkOrder> NewWosMap =  new Map<Id,WorkOrder>(newItems);
        Map<Id,List<Plc_UnsuccessfulExit__c>> woUnsfExitRsMap = new Map<Id,List<Plc_UnsuccessfulExit__c>>();
        Plc_UnsuccessfulExit__c[] allwoUnsfExitRsList = [SELECT Id, Plc_WorkOrder__c,Plc_ExitReason__c,Plc_Status__c FROM Plc_UnsuccessfulExit__c WHERE Plc_WorkOrder__c IN :NewWosMap.keyset()];
        for(WorkOrder wo : NewWosMap.values()){
            List<Plc_UnsuccessfulExit__c> woUnsfExitRs = new List<Plc_UnsuccessfulExit__c>();
            for(Plc_UnsuccessfulExit__c UnsfExitR :allwoUnsfExitRsList){
                if(UnsfExitR.Plc_WorkOrder__c==wo.Id)woUnsfExitRs.add(UnsfExitR);
            }
            if(!woUnsfExitRs.isEmpty())woUnsfExitRsMap.put(wo.id,woUnsfExitRs);
        }
        return woUnsfExitRsMap;
    }

}