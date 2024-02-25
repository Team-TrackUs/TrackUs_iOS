//
//  CourseDetailView.swift
//  TrackUs
//
//  Created by 석기권 on 2024/02/22.
//

import SwiftUI
import MapboxMaps

struct CourseDetailView: View {
    private let authViewModel = AuthenticationViewModel.shared
    @EnvironmentObject var router: Router
    @StateObject var userSearchViewModel = UserSearchViewModel()
    @ObservedObject var courseViewModel: CourseViewModel
    
    var body: some View {
        VStack {
            PathPreviewMap(
                mapStyle: .numberd,
                coordinates: courseViewModel.course.coordinates
            )
            .frame(height: 230)
            
            ScrollView {
                VStack(spacing: 0)   {
                    RunningStatsView(estimatedTime: Double(courseViewModel.course.estimatedTime), calories: 0, distance: courseViewModel.course.coordinates.caculateTotalDistance() / 1000.0)
                        .padding(.top, 20)
                    
                    courseDetailLabels
                        .padding(.top, 20)
                    
                    participantList
                        .padding(.top, 20)
                    
                }
                .padding(.horizontal, 16)
            }
            VStack {
                let memberContains = courseViewModel.course.members.contains(authViewModel.userInfo.uid)
                if courseViewModel.course.members.count >= courseViewModel.course.participants {
                    MainButton(active: false, buttonText: "해당 러닝은 마감되었습니다.") {
                    }
                  
                }
                else if !memberContains {
                    MainButton(buttonText: "러닝 참가하기") {
                        courseViewModel.addParticipant(uid: courseViewModel.course.uid)
                    }
                } else if memberContains {
                    MainButton(active: true, buttonText: "러닝 참가취소 ", buttonColor: .Caution) {
                        courseViewModel.removeParticipant(uid: courseViewModel.course.uid)
                    }
                }
                
            }
            .padding(.horizontal, 16)
        }
        .customNavigation {
            NavigationText(title: "모집글 상세보기")
        } left: {
            NavigationBackButton()
        }
        
    }
}

extension CourseDetailView {
    
    // 제목, 부가설명 등등
    var courseDetailLabels: some View {
        VStack {
            HStack {
                Text(courseViewModel.course.startDate.formattedString())
                    .customFontStyle(.gray2_R12)
                Spacer()
                RunningStyleBadge(style: .init(rawValue: courseViewModel.course.runningStyle) ?? .running)
            }
            
            VStack(alignment: .leading) {
                Text(courseViewModel.course.title)
                    .customFontStyle(.gray1_B20)
                
                HStack(spacing: 10) {
                    HStack {
                        Image(.pin)
                        
                        Text(courseViewModel.course.address)
                            .customFontStyle(.gray1_R12)
                            .lineLimit(1)
                    }
                    
                    HStack {
                        Image(.arrowBoth)
                        Text(courseViewModel.course.distance.asString(unit: .kilometer))
                            .customFontStyle(.gray1_R12)
                    }
                }
                
                Text(courseViewModel.course.content)
                    .customFontStyle(.gray1_R14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // 참여자 리스트
    
    var participantList: some View {
        VStack(alignment: .leading) {
            UserList(users: userSearchViewModel.filterdUserData(uid: courseViewModel.course.members), ownerUid: courseViewModel.course.ownerUid)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

