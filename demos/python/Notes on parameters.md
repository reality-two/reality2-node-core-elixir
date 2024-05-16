There are three sets of parameters

1) Passthrough parameters
    These start life as 'passthrough' parameters (a JSON object) when you send an event to a Sentant.  If that event subsequently causes actions to occur, then each of those actions get the passthrough parameters.  The intention is that they are not used, just passed through.  Eventually, they will pass through to the output as part of a response, if there is one, for example, the sending of a signal.

    In a similar way, when setting up a subscription to a signal, passthrough parameters can be specified.  When the subscription is triggered, those parameters will be present in the signal + parameters that are sent out.

2) Event parameters
    Every event sent in has parameters, a JSON object.  If there are actions, the first action gets these parameters, added to by the parameters of the action.  Each action may then modify the parameters, adding to them, altering the values, or deleting from them, as they are passed to the next action.
    Each action has parameters as well which are part of the action definition.  These values are added to the incoming parameters, overriding any that have the same key.