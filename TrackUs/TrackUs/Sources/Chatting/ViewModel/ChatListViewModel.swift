//
//  ChatListViewModel.swift
//  TrackUs
//
//  Created by 최주원 on 2/23/24.
//

import Foundation
import FirebaseFirestore

class ChatListViewModel: ObservableObject {
    static let shared = ChatListViewModel()
    // 채팅방 정보
    @Published var chatRooms: [ChatRoom] = []
    @Published var users: [String: Member] = [:]
    @Published var currentUId: String
    @Published var newMessage: Bool
    
    // 신규 메세지 총 카운트 갯수
    var messageCount: String? {
        let count = chatRooms.reduce (0, { $0 + ($1.usersUnreadCountInfo[currentUId] ?? 0) })
        UIApplication.shared.applicationIconBadgeNumber = count
        switch count{
            case 1...999: return String(count)
            case 999...: return "999+"
            default: return nil
        }
    }
    
    init() {
        
        self.chatRooms = []
        self.users = [:]
        self.newMessage = false
        if let currentUId = FirebaseManger().auth.currentUser?.uid {
            self.currentUId = currentUId
            //subscribeToUpdates()
        }else{
            self.currentUId = ""
        }
    }
    
    // 변환 방식 -> chatRoom -> currentUId 포함된 맴버 목록(uid) 불러오기 -> 포함된 userInfo 리스너 추가?
    private let ref = FirebaseManger().firestore.collection("chatRoom")
    
    // 채팅방 생성 - 글쓰기 시점
    func createGroupChatRoom(trackId: String,title: String, uid: String) {
        let newChatRoom: [String: Any] = [
            "title": title,
            "group": true,
            "members": [uid],
            "usersUnreadCountInfo": [uid: 0]
            //"latestMessage": nil
        ]  as [String : Any]
        ref.document(trackId).setData(newChatRoom)
    }
    
    // 채팅방 참여
    func joinChatRoom(chatRoomID: String, userUID: String) {
        ref.document(chatRoomID).updateData([
            "members": FieldValue.arrayUnion([userUID])
        ]) { error in
            if let error = error {
                print("Error updating document: \(error)")
            }
        }
        
        ref.document(chatRoomID).updateData([
            "usersUnreadCountInfo.\(userUID)": 0
        ]) { error in
            if let error = error {
                print("Error updating document: \(error)")
            }
        }
    }
    
    // 채팅방 나가기
    func leaveChatRoom(chatRoomID: String, userUID: String) {
        ref.document(chatRoomID).updateData([
            "members": FieldValue.arrayRemove([userUID])
        ]) { error in
            if let error = error {
                print("Error updating document: \(error)")
            }
        }
    }
    
    // 채팅방 삭제
    func deleteChatRoom(chatRoomID: String) {
        ref.document(chatRoomID).delete{ error in }
    }
    
    // MARK: - 채팅방 리스너 관련
    // 채팅방 listener 추가
    func subscribeToUpdates() {
        guard let currentUId = FirebaseManger().auth.currentUser?.uid else { return }
        ref.whereField("members", arrayContains: currentUId).addSnapshotListener() { [weak self] (snapshot, _) in
            self?.storeChatRooms(snapshot, currentUId)
        }
        
    }
    
    // 채팅방 Firebase 정보 가져오기
    private func storeChatRooms(_ snapshot: QuerySnapshot?, _ currentUId: String) {
        DispatchQueue.main.async { [weak self] in
            self?.chatRooms = snapshot?.documents
                .compactMap { [weak self] document in
                    do {
                        let firestoreChatRoom = try document.data(as: FirestoreChatRoom.self)
                        return self?.makeChatRooms(document.documentID, firestoreChatRoom, currentUId)
                    } catch {
                        print(error)
                    }

                    return nil
                }.sorted {
                    if let date1 = $0.latestMessage?.timestamp, let date2 = $1.latestMessage?.timestamp {
                        return date1 > date2
                    }
                    return $0.title < $1.title
                }
            ?? []
        }
    }
    
    // ChatRoom타입에 맞게 변환
    private func makeChatRooms(_ id: String, _ firestoreChatRoom: FirestoreChatRoom, _ currentUId: String) -> ChatRoom {
        var message: LatestMessageInChat? = nil
        if let flm = firestoreChatRoom.latestMessage {
            message = LatestMessageInChat(
                //senderName: user.name,
                timestamp: flm.timestamp,
                text: flm.text.isEmpty ? "사진을 보냈습니다." : flm.text
            )
        }
        let members = firestoreChatRoom.members
        _ = firestoreChatRoom.members.map { memberId in
            memberUserInfo(uid: memberId)
        }
        let chatRoom = ChatRoom(
            id: id,
            title: firestoreChatRoom.title,
            members: members,
            nonSelfMembers: members.filter { $0 != currentUId },
            usersUnreadCountInfo: firestoreChatRoom.usersUnreadCountInfo,
            group: firestoreChatRoom.group,
            latestMessage: message
        )
        return chatRoom
    }
    
    // 리스너 추가? 아님 별도로 기록?
    // 채팅방 멤버 닉네임, 프로필사진url 불러오기
    private func memberUserInfo(uid: String) {
        FirebaseManger.shared.firestore.collection("users").document(uid).addSnapshotListener { documentSnapshot, error in
            guard let document = documentSnapshot else {
                // 탈퇴 사용자인 경우 리스트에서 삭제
                self.chatRooms = self.chatRooms.map{
                    var chatRomm = $0
                    chatRomm.members = $0.members.filter{ $0 != uid }
                    chatRomm.nonSelfMembers = $0.nonSelfMembers.filter{ $0 != uid }
                    return chatRomm
                }
                return
            }
            do {
                var userInfo = try document.data(as: UserInfo.self)
//                if userInfo.isBlock {
//                    userInfo.username = "정지 회원"
//                    userInfo.profileImageUrl = nil
//                    userInfo.token = nil
//                }
                self.users[uid] = Member(uid: uid, userName: userInfo.username, profileImageUrl: userInfo.profileImageUrl, token: userInfo.token)
            } catch {
                print("Error decoding document: \(error)")
            }
        }
    }
}
