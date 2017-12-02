//
//  UserEventsController.swift
//  groupLists
//
//  Created by Kyle Cross on 10/19/17.
//  Copyright © 2017 bergerMacPro. All rights reserved.
//
import Foundation
import Firebase

class UserEventsController {
    var events: [Event] = []
    var ref : DatabaseReference!
    
    
    //creates an event, appends it to events array
    func createEvent(name: String, description: String, date: Date, userController:
        UserController) {
        
        //format date as string for firebase
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = formatter.string(from: date)
        
        //send data to firebase
        ref = Database.database().reference()
        
        //gets autogenerated id
        let eventRef = ref.child(DB.events).childByAutoId()
        
        //get user name
        let userName = userController.user.firstName + " " + userController.user.lastName
        
        //get user email
        let userEmail = userController.user.email
        
        //set values of event
        eventRef.setValue([DB.name: name, DB.date: dateString, DB.description: description, DB.creator: userController.user.id])
        eventRef.child(DB.authorizedUsers).child(userController.user.id).setValue([DB.userName: userName, DB.permissions: true, DB.email: userEmail])
        
        //add the event to the users events list
        ref.child(DB.users).child(userController.user.id).child(DB.events).child(eventRef.key).setValue(true)
        
        let authorizedUserStruct = AuthorizedUser(userId: userController.user.id, userName: userName, userEmail: userEmail, permissions: true)
        
        events.append(Event(name: name, id: eventRef.key, date: date, description: description, creator: userController.user.id, authorizedUsers: [authorizedUserStruct]))
    }
    
    
    
    func addUserToEvent(eventID: String, eventIdx: Int, email: String, permissions: Bool, addUserVC: ManipulateUsersController) {
        //query for user's key based on user's email
        ref.child(DB.users).queryOrdered(byChild:  "email").queryStarting(atValue: email).queryEnding(atValue: email).observeSingleEvent(of: .value, with: { (snapshot) in
            let user = snapshot.value as? NSDictionary
            
            if user != nil {
                // get user's id and name
                let userID = user!.allKeys[0] as? String
                let userDict = user![userID!] as? NSDictionary ?? [:]
                let userName = (userDict[DB.firstName]! as? String ?? "") + " " + (userDict[DB.lastName]! as? String ?? "")
                
                //add user to event's authorizedUsers
                self.ref.child(DB.events).child(eventID).child(DB.authorizedUsers).child(userID!).setValue([DB.userName: userName, DB.permissions: permissions, DB.email: email])
                
                // Append user to event's authorized users list
                let authorizedUserStruct = AuthorizedUser(userId: userID!, userName: userName, userEmail: email, permissions: permissions)
                self.events[eventIdx].authorizedUsers.append(authorizedUserStruct)
                
                //add the event to the user's events list
                self.ref.child(DB.users).child(userID!).child(DB.events).child(eventID).setValue(true)
                
                //reload table view displaying current authorizedUsers
                addUserVC.currentUsersTableView.reloadData()
                
                //ensure table view height accomodates new user add
                addUserVC.updateViewConstraints()
                
            } else {
                //alert user that the other user doesn't exist
                let alert = UIAlertController(title: "Error", message: "User does not exist", preferredStyle: .alert)
                let ok = UIAlertAction(title: "Ok", style: .default)
                
                alert.addAction(ok)
                addUserVC.present(alert, animated: true, completion: nil)
            }
        })
    }
    
    func removeUserFromEvent(eventIdx: Int, user: AuthorizedUser, addUserVC: ManipulateUsersController) {
        
        //ensure valid index
        if (eventIdx < self.events.count) {
            
            self.ref = Database.database().reference()
            //remove userID from event's authorizedUsers array
            self.ref.child(DB.events).child(self.events[eventIdx].id).child(DB.authorizedUsers).child(user.userId).removeValue()
            //remove event from user's events array
            self.ref.child(DB.users).child(user.userId).child(DB.events).child(self.events[eventIdx].id).removeValue()
            
            //remove user from local authorizedUsers array
            self.events[eventIdx].authorizedUsers = self.events[eventIdx].authorizedUsers.filter( {$0.userId != user.userId} )
            //update current user view and adjust view's height accordingly
            addUserVC.currentUsersTableView.reloadData()
            addUserVC.updateViewConstraints()
        }
    }
    
    
    
    func editEvent(eventIdx: Int, name: String? = nil, date: Date? = nil, description: String? = nil, user: UserController) -> Bool{
        if hasPrivileges(index: eventIdx, user: user) == false {
            //show message that they aren't allowed to edit
            return false
        }
        
        if eventIdx <= events.count {
            
            let event = self.events[eventIdx]
            
            let newName = name ?? event.name
            let newDate = date ?? event.date
            let newDescription = description ?? event.description
            
            //update event locally
            event.name = newName
            event.date = newDate
            event.description = newDescription
            
            //edit event in database
            ref = Database.database().reference().child(DB.events).child(event.id)
            
            //format date as string for firebase
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let dateString = formatter.string(from: newDate)
            
            let e = [DB.date: dateString,
                     DB.description: newDescription,
                     DB.name: newName] as [String : Any]
            
            ref.updateChildValues(e)
            
            return true
            
        } else {
            
            print("Invalid event index provided")
            return false
        }
    }
    
    
    
    //remove event from database and user's events list
    func removeEvent(user: UserController, eventIdx: Int) -> Bool{
        if hasPrivileges(index: eventIdx, user: user) == false {
            //show message that they aren't allowed to delete
            return false
        }
        
        if eventIdx <= events.count {
            let event = self.events[eventIdx]
            
            ref = Database.database().reference()
            
            //removes from database
            ref.child(DB.events).child(event.id).removeValue()
            //remove from current user's list
            ref.child(DB.users).child(user.user.id).child(DB.events).child(event.id).removeValue()
            
            //remove event from events array
            for x in 0..<events.count {
                if events[x].id == event.id {
                    events.remove(at: x)
                    return true
                }
            }
            
        } else {
            
            print("Invalid event index provided")
            return false
            
        }
        return false
    }
    
    
    
    //get user's events from FireBase
    func getDBEvents(userId: String, eventCollectionView: UICollectionView) {
        ref = Database.database().reference()
        var events_list: [String] = []
        
        
        
        ref.child(DB.users).child(userId).child(DB.events).queryOrderedByKey().observeSingleEvent(of: .value, with: { (snapshot) in
            let user_events = snapshot.value as? NSDictionary
           
            if user_events != nil {
                
                for e in user_events! {
                    events_list.append(e.key as! String)
                }
                
                for key in events_list {
                    self.ref.child(DB.events).child(key).observeSingleEvent(of: .value, with: { (snapshot) in
                        let event = snapshot.value as? NSDictionary
                        
                        if event != nil {
                            let id = key
                            let description = event?[DB.description] as? String ?? ""
                            let name = event?[DB.name] as? String ?? ""
                            let dateString = event?[DB.date] as? String ?? "0000-00-00 00:00:00"
                            let creator = event?[DB.creator] as? String ?? ""
                            let authorizedUsersDict = event?[DB.authorizedUsers] as? NSDictionary ?? [:]
                            
                            // Convert authorized users dictionary to array
                            var authorizedUsers : [AuthorizedUser] = []
                            
                            for u in authorizedUsersDict {
                                let user = u.value as? NSDictionary ?? [:]
                                let userId = u.key as? String ?? ""
                                let permissions = user[DB.permissions] as? Bool ?? false
                                let userName = user[DB.userName] as? String ?? ""
                                let userEmail = user[DB.email] as? String ?? ""
                                
                                authorizedUsers.append(AuthorizedUser(userId: userId, userName: userName, userEmail: userEmail, permissions: permissions))
                            }
                            
                            // format date from string to date type
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                            let date = formatter.date(from: dateString)
                            
                            let temp_event = Event(name: name, id: id, date: date!, description: description, creator: creator, authorizedUsers: authorizedUsers)
                            
                            self.events.append(temp_event)
                        } else {
                            //event has been deleted so remove from user's events list
                            self.ref.child(DB.users).child(userId).child(DB.events).child(key).removeValue()
                        }
                        
                        eventCollectionView.reloadData()
                    }) { (error) in
                        print(error.localizedDescription)
                    }
                }
            }
        }) { (error) in
            print(error.localizedDescription)
        }
    }
    
    //checks if user has edit/delete privileges
    func hasPrivileges(index: Int, user: UserController) -> Bool {
        let e = events[index]
        
        if e.creator == user.user.id {
            print("has privileges")
            return true
        }
        
        for u in e.authorizedUsers {
            if u.userId == user.user.id && u.permissions == true {
                print("has privileges")
                return true
            }
        }
        
        print("does not have privileges")
        return false
    }
    
    //get name of event creator
    func getCreatorName(index: Int) -> String {
        
        for user in self.events[index].authorizedUsers {
            if user.userId == self.events[index].creator {
                return user.userName
            }
        }
        
        return "unknown"
    }
}
